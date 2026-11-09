import Foundation

/// PLAN §4.1 "Nested checkouts", one way for a worktree (`WorktreeInspector`) and for a light-clean folder
/// (`LightCleanCheck`): every repo below a folder, sorted into
/// - registered worktrees and `.git` files: always blocking;
/// - package copies (`PackageCopyRule`, decided without running git in them): build output;
/// - every other clone or bare repo, by what `NestedCloneCheck` finds in it.
///
/// The search goes on inside every repo the check lets go of: package copies, clean clones, and their own submodules
/// (P12b review, 11-09: a repo with work at `.build/checkouts/x/vendor/mine`, or below a clean clone whose own
/// `.gitignore` hides it, was invisible, and Remove and light clean deleted it). Each search skips that repo's own
/// `.git`. What that repo tracks is its content, not a nested repo: a bare-shaped folder whose `HEAD` it tracks
/// (libgit2-style committed fixtures), asked with its own `git ls-files -z` only when such a folder is found and its
/// config runs nothing; when git can't list them, the folder keeps the rule (the safe side). A `.git` file that
/// leads into the let-go repo's own modules is its submodule: a package copy's is let go as build output; a clean
/// clone's goes through `NestedCloneCheck` by its git dir (round 3: a commit on a branch only in
/// `lib/.git/modules/sub` was deleted). Any other repo found keeps the rule above. A bare repo is all git's own data
/// and isn't searched. The entry cap counts every folder searched; hitting it makes the search incomplete.
struct NestedRepoFinder: Sendable {
    var git: Git
    var search: NestedCheckoutSearch

    struct Findings: Sendable {
        /// Registered worktrees and `.git` files, relative to the folder searched.
        var worktrees: [String] = []
        var copies: [String] = []
        /// Every other repo with what `NestedCloneCheck` found, in path order.
        var others: [(path: String, verdict: NestedCloneCheck.Verdict)] = []
        var incomplete: String?
    }

    /// A repo the check let go of, to search inside: its path, its git dir, where its own submodules' git dirs live,
    /// and whether it is a package copy (or one's submodule), whose submodules are build output too.
    private struct LetGo {
        var path: String
        var gitDir: URL
        var modules: URL
        var isCopy: Bool

        init(path: String, in folder: URL, isCopy: Bool) {
            self.path = path
            gitDir = folder.appending(path: path + "/.git", directoryHint: .isDirectory)
            modules = gitDir.appending(path: "modules", directoryHint: .isDirectory)
            self.isCopy = isCopy
        }

        init(submodule path: String, gitDir: URL, isCopy: Bool) {
            self.path = path
            self.gitDir = gitDir
            modules = gitDir.appending(path: "modules", directoryHint: .isDirectory)
            self.isCopy = isCopy
        }
    }

    /// `prefix`: `folder` relative to `worktree` (the checkout whose git answers), "" when it is the checkout itself.
    func find(in folder: URL, worktree: URL, prefix: String, knownWorktrees: [Worktree]) async -> Findings {
        let top = search.search(folder)
        let registered = knownWorktrees.compactMap { CanonicalPath.relativePath(of: $0.url, to: folder) }.filter { $0 != "." }
        let candidates = top.checkouts.filter { !registered.contains($0) && !top.gitFiles.contains($0) }
        let fromRoot = { (path: String) in prefix.isEmpty ? path : prefix + "/" + path }
        let copiesFromRoot = await PackageCopyRule(git: git, worktree: worktree).copies(among: candidates.map(fromRoot))
        let copies = candidates.filter { copiesFromRoot.contains(fromRoot($0)) }.sorted()

        var findings = Findings(copies: copies, incomplete: top.incomplete)
        var gitFiles = top.gitFiles
        var bare = Set(top.bareRepos)
        var used = top.entries
        var toCheck = candidates.filter { !copies.contains($0) }
        var letGo = copies.map { LetGo(path: $0, in: folder, isCopy: true) }
        var submodulesToCheck: [(path: String, gitDir: URL)] = []
        var others: [(path: String, verdict: NestedCloneCheck.Verdict)] = []
        let check = NestedCloneCheck(git: git)
        while true {
            if !toCheck.isEmpty {
                let verdicts = await check.verdicts(toCheck, in: folder)
                for path in toCheck.sorted() {
                    guard let verdict = verdicts[path] else { continue }
                    others.append((path, verdict))
                    if verdict == .clean { letGo.append(LetGo(path: path, in: folder, isCopy: false)) }
                }
                toCheck = []
            }
            for (path, gitDir) in submodulesToCheck {
                let verdict = await check.verdict(folder.appending(path: path, directoryHint: .isDirectory), submoduleGitDir: gitDir)
                others.append((path, verdict))
                if verdict == .clean { letGo.append(LetGo(submodule: path, gitDir: gitDir, isCopy: false)) }
            }
            submodulesToCheck = []
            guard findings.incomplete == nil, !letGo.isEmpty else { break }
            let repo = letGo.removeFirst()
            if bare.contains(repo.path) { continue }
            let url = folder.appending(path: repo.path, directoryHint: .isDirectory)
            let inside = NestedCheckoutSearch(limit: max(0, search.limit - used)).search(url)
            used += inside.entries
            if let why = inside.incomplete { findings.incomplete = "inside \(repo.path): \(why)" }
            let tracked = inside.bareRepos.isEmpty ? [] : await trackedFiles(in: url, gitDir: repo.gitDir)
            for found in inside.checkouts {
                let path = repo.path + "/" + found
                if registered.contains(path) { continue }
                // Committed test fixtures shaped like a bare repo: the let-go repo's own content.
                if inside.bareRepos.contains(found), tracked.contains(found + "/HEAD") { continue }
                guard inside.gitFiles.contains(found) else {
                    if inside.bareRepos.contains(found) { bare.insert(path) }
                    toCheck.append(path)
                    continue
                }
                // The let-go repo's own submodule: a copy's is build output, a clean clone's is checked through its git
                // dir; any other `.git` file blocks.
                if let target = Self.gitFileTarget(url.appending(path: found + "/.git")),
                   CanonicalPath.isInside(target, directory: repo.modules) {
                    if repo.isCopy {
                        letGo.append(LetGo(submodule: path, gitDir: target, isCopy: true))
                    } else {
                        submodulesToCheck.append((path, target))
                    }
                } else {
                    gitFiles.append(path)
                }
            }
        }
        findings.worktrees = (registered + gitFiles).uniqued().sorted()
        findings.others = others.sorted { $0.path < $1.path }
        return findings
    }

    /// What the repo at `url` tracks (`git ls-files -z`, run inside it), relative to it. Empty when its config could
    /// run something or git can't list them: then nothing counts as its content (the safe side).
    private func trackedFiles(in url: URL, gitDir: URL) async -> Set<String> {
        guard case .success(let config) = await NestedRepoConfig.read(gitDir: gitDir, git: git), config.commandKeys.isEmpty,
              let listing = try? await git.git(["ls-files", "-z"], in: url)
        else { return [] }
        return Set(listing.split(separator: 0).map { String(decoding: $0, as: UTF8.self) })
    }

    /// Where a `.git` file leads ("gitdir: <path>", relative to the file's folder); nil when it can't be read.
    static func gitFileTarget(_ file: URL) -> URL? {
        guard let data = try? Data(contentsOf: file), data.count < 4_096,
              let line = String(data: data, encoding: .utf8)?.split(whereSeparator: \.isNewline).first,
              line.hasPrefix("gitdir: ")
        else { return nil }
        let path = String(line.dropFirst("gitdir: ".count))
        return path.hasPrefix("/") ? URL(fileURLWithPath: path)
            : URL(fileURLWithPath: path, relativeTo: file.deletingLastPathComponent()).standardizedFileURL
    }
}
