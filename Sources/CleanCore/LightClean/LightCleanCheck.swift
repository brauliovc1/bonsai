import Foundation

/// The PLAN §4.2 light-clean conditions for one folder, plus the nested-checkout rule of §4.1. Read-only.
/// `LightCleanFinder` runs it for every folder whose name matched, and `LightCleaner` runs it again right
/// before deleting each candidate.
///
/// `check-ignore` and `ls-files` run in the folder's parent with the folder's name: run inside the folder,
/// git would apply the folder's own `.gitignore` to the folder itself. The names in `RegenerableNames` are
/// ASCII, so they reach git unchanged; the parent's path only goes to `-C` (a chdir, which matches names
/// whatever their Unicode form). `ls-files` matches the name case-insensitively (`:(icase)`), and the
/// worktree's `git status` must list nothing under the folder.
struct LightCleanCheck: Sendable {
    var git: Git
    var nestedSearch: NestedCheckoutSearch

    struct Verdict: Sendable, Hashable {
        /// nil = the folder may be deleted.
        var reason: LightCleanSkipReason?
        /// Repos with no local work inside, which go with the folder.
        var packageClones: [String] = []
        /// The folder as lstat saw it when the checks began, for the re-check right before deleting.
        var identity: FileIdentity?
    }

    /// `relative`: the folder, relative to `worktree`. `status`: the worktree's status, read beforehand.
    /// `knownWorktrees`: every registered worktree of every scanned repo; one inside the folder keeps it.
    func verdict(
        for relative: String,
        in worktree: URL,
        status: LightCleanStatus,
        knownWorktrees: [Worktree]
    ) async -> Verdict {
        if let problem = Self.pathProblem(relative, in: worktree.path) { return Verdict(reason: problem) }
        let folder = worktree.appending(path: relative, directoryHint: .isDirectory)
        let identity = FileIdentity.of(folder.path)
        if Remover.itemExists(at: folder.appending(path: ".git").path) || NestedCheckoutSearch.isBareRepo(folder) {
            return Verdict(reason: .nestedCheckout(["."]))
        }
        let name = relative.split(separator: "/").last.map(String.init) ?? relative
        if let reason = await gitReason(name: name, parent: folder.deletingLastPathComponent(), worktree: worktree) {
            return Verdict(reason: reason)
        }
        let changed = status.paths(under: relative)
        if !changed.isEmpty { return Verdict(reason: .uncommittedFiles(changed)) }
        var verdict = await nestedVerdict(folder, knownWorktrees: knownWorktrees)
        verdict.identity = identity
        return verdict
    }

    /// Every folder from the worktree root down to `relative` must be a real folder, the last one included:
    /// a symlink on the way would aim a delete elsewhere, and a symlink as the folder would delete the link.
    static func pathProblem(_ relative: String, in root: String) -> LightCleanSkipReason? {
        guard FileIdentity.of(root)?.kind == .directory else { return .notACandidate("the worktree folder is not a plain folder") }
        let parts = relative.split(separator: "/")
        var path = root
        for (index, part) in parts.enumerated() {
            path += "/" + part
            let shown = parts[...index].joined(separator: "/")
            let isLast = index == parts.count - 1
            switch FileIdentity.of(path)?.kind {
            case .directory: continue
            case .symlink: return isLast ? .symlink : .notACandidate("\(shown) is not a plain folder")
            case .other, nil: return isLast ? .gone : .notACandidate("\(shown) is not a plain folder")
            }
        }
        return nil
    }

    /// Tracked files, then ignored, as git sees them from the folder's parent. A git failure is a reason
    /// too. Tracked files are asked first: git calls a folder with tracked files in it "not ignored".
    private func gitReason(name: String, parent: URL, worktree: URL) async -> LightCleanSkipReason? {
        do {
            // git must answer for this worktree, not for a repo around it (a broken `.git` file).
            let topLevel = try await git.gitString(["rev-parse", "--show-toplevel"], in: parent)
            guard CanonicalPath.same(URL(fileURLWithPath: topLevel), worktree) else {
                return .gitError("git sees \(topLevel) here, not this worktree")
            }
            if !(try await git.git(["ls-files", "-z", "--", ":(icase)\(name)"], in: parent)).isEmpty { return .hasTrackedFiles }
            let ignore = try await git.result(["check-ignore", "-q", "--", name], in: parent)
            if ignore.timedOut { return .gitError("git check-ignore timed out") }
            switch ignore.exitCode {
            case 0: return nil
            case 1: return .notIgnored
            default:
                let message = ignore.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return .gitError("git check-ignore failed (exit \(ignore.exitCode))" + (message.isEmpty ? "" : ": \(message)"))
            }
        } catch {
            return .gitError("\(error)")
        }
    }

    /// `.git` files and registered worktrees always keep the folder; a plain clone or bare repo keeps it
    /// unless it holds no local work (`NestedCloneCheck`). A search that can't finish keeps it too.
    private func nestedVerdict(_ folder: URL, knownWorktrees: [Worktree]) async -> Verdict {
        let search = nestedSearch.search(folder)
        let registered = knownWorktrees.compactMap { CanonicalPath.relativePath(of: $0.url, to: folder) }
        let plain = search.checkouts.filter { !registered.contains($0) && !search.gitFiles.contains($0) }
        let clean = await NestedCloneCheck(git: git).clonesWithoutLocalWork(plain, in: folder)
        let blocking = (registered + search.gitFiles + plain.filter { !clean.contains($0) }).uniqued().sorted()
        if !blocking.isEmpty { return Verdict(reason: .nestedCheckout(blocking)) }
        if let why = search.incomplete { return Verdict(reason: .nestedSearchIncomplete(why)) }
        return Verdict(reason: nil, packageClones: plain.filter(clean.contains).sorted())
    }
}
