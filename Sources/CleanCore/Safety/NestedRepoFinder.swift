import Foundation

/// PLAN §4.1 "Nested checkouts", one way for a worktree (`WorktreeInspector`) and for a light-clean folder
/// (`LightCleanCheck`): every repo below a folder, sorted into
/// - registered worktrees and `.git` files: always blocking;
/// - package copies (`PackageCopyRule`, decided without running git in them): build output;
/// - every other clone or bare repo, by what `NestedCloneCheck` finds in it.
///
/// The search goes on inside each package copy, skipping its own `.git` (P12b review, 11-09: a repo with work at
/// `.build/checkouts/x/vendor/mine` was invisible, and Remove and light clean deleted it). A repo found there is not a
/// copy and keeps the rule above; a `.git` file that leads into the copy's own `.git/modules` is the copy's submodule
/// and belongs to it. The entry cap counts every folder searched, inside copies too.
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

    /// `prefix`: `folder` relative to `worktree` (the checkout whose git answers), "" when it is the checkout itself.
    func find(in folder: URL, worktree: URL, prefix: String, knownWorktrees: [Worktree]) async -> Findings {
        let top = search.search(folder)
        let registered = knownWorktrees.compactMap { CanonicalPath.relativePath(of: $0.url, to: folder) }.filter { $0 != "." }
        let candidates = top.checkouts.filter { !registered.contains($0) && !top.gitFiles.contains($0) }
        let fromRoot = { (path: String) in prefix.isEmpty ? path : prefix + "/" + path }
        let copiesFromRoot = await PackageCopyRule(git: git, worktree: worktree).copies(among: candidates.map(fromRoot))
        let copies = candidates.filter { copiesFromRoot.contains(fromRoot($0)) }

        var findings = Findings(copies: copies.sorted(), incomplete: top.incomplete)
        var gitFiles = top.gitFiles
        var others = candidates.filter { !copies.contains($0) }
        var used = top.entries
        // Inside each clone that is a copy (a bare copy is all git's own data): what else lives there.
        for copy in copies.sorted() where !top.bareRepos.contains(copy) && findings.incomplete == nil {
            let copyURL = folder.appending(path: copy, directoryHint: .isDirectory)
            let inside = NestedCheckoutSearch(limit: max(0, search.limit - used)).search(copyURL)
            used += inside.entries
            if let why = inside.incomplete { findings.incomplete = "inside \(copy): \(why)" }
            let ownModules = copyURL.appending(path: ".git/modules", directoryHint: .isDirectory)
            for found in inside.checkouts {
                let path = copy + "/" + found
                if registered.contains(path) { continue }
                if inside.gitFiles.contains(found) {
                    let target = Self.gitFileTarget(copyURL.appending(path: found + "/.git"))
                    if let target, CanonicalPath.isInside(target, directory: ownModules) { continue }
                    gitFiles.append(path)
                } else {
                    others.append(path)
                }
            }
        }
        findings.worktrees = (registered + gitFiles).uniqued().sorted()
        let verdicts = await NestedCloneCheck(git: git).verdicts(others, in: folder)
        findings.others = others.sorted().compactMap { path in verdicts[path].map { (path, $0) } }
        return findings
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
