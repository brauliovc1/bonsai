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
/// `.git`. A repo found there is not a copy and keeps the rule above; a `.git` file that leads into the let-go repo's
/// own modules (`.git/modules`) is its submodule, let go and searched in turn. A bare repo is all git's own data and
/// isn't searched. The entry cap counts every folder searched; hitting it makes the search incomplete.
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

    /// A repo the check let go of, to search inside: its path and where its own submodules' git dirs live.
    private struct LetGo {
        var path: String
        var modules: URL
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
        var letGo = copies.map { LetGo(path: $0, modules: Self.ownModules(of: $0, in: folder)) }
        var others: [(path: String, verdict: NestedCloneCheck.Verdict)] = []
        while true {
            if !toCheck.isEmpty {
                let verdicts = await NestedCloneCheck(git: git).verdicts(toCheck, in: folder)
                for path in toCheck.sorted() {
                    guard let verdict = verdicts[path] else { continue }
                    others.append((path, verdict))
                    if verdict == .clean { letGo.append(LetGo(path: path, modules: Self.ownModules(of: path, in: folder))) }
                }
                toCheck = []
            }
            guard findings.incomplete == nil, !letGo.isEmpty else { break }
            let repo = letGo.removeFirst()
            if bare.contains(repo.path) { continue }
            let url = folder.appending(path: repo.path, directoryHint: .isDirectory)
            let inside = NestedCheckoutSearch(limit: max(0, search.limit - used)).search(url)
            used += inside.entries
            if let why = inside.incomplete { findings.incomplete = "inside \(repo.path): \(why)" }
            for found in inside.checkouts {
                let path = repo.path + "/" + found
                if registered.contains(path) { continue }
                guard inside.gitFiles.contains(found) else {
                    if inside.bareRepos.contains(found) { bare.insert(path) }
                    toCheck.append(path)
                    continue
                }
                // The let-go repo's own submodule: let go too, and searched; any other `.git` file blocks.
                if let target = Self.gitFileTarget(url.appending(path: found + "/.git")),
                   CanonicalPath.isInside(target, directory: repo.modules) {
                    letGo.append(LetGo(path: path, modules: target.appending(path: "modules", directoryHint: .isDirectory)))
                } else {
                    gitFiles.append(path)
                }
            }
        }
        findings.worktrees = (registered + gitFiles).uniqued().sorted()
        findings.others = others.sorted { $0.path < $1.path }
        return findings
    }

    /// Where the git dirs of `path`'s own submodules live: `<path>/.git/modules`.
    private static func ownModules(of path: String, in folder: URL) -> URL {
        folder.appending(path: path + "/.git/modules", directoryHint: .isDirectory)
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
