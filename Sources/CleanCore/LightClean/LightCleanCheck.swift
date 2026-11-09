import Foundation

/// The PLAN §4.2 light-clean conditions for one folder, plus the nested-checkout rule of §4.1 (package copies
/// included). Read-only. `LightCleanFinder` runs it for every folder whose name matched, and `LightCleaner`
/// runs it again right before deleting each candidate.
///
/// git must ignore the folder and track nothing in it (`IgnoredOutputCheck`, asked from the folder's parent),
/// and the worktree's `git status` must list nothing under the folder.
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
        var verdict = await nestedVerdict(folder, relative: relative, in: worktree, knownWorktrees: knownWorktrees)
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

    /// Tracked files, then ignored, as git sees them from the folder's parent (`IgnoredOutputCheck`).
    private func gitReason(name: String, parent: URL, worktree: URL) async -> LightCleanSkipReason? {
        await IgnoredOutputCheck(git: git).reason(name: name, parent: parent, worktree: worktree)
    }

    /// `.git` files and registered worktrees always keep the folder. A plain clone or bare repo goes with it
    /// when it is a package copy (decided without running git in it) or holds no local work; any other keeps it,
    /// also one inside a copy (`NestedRepoFinder`). A search that can't finish keeps it too.
    private func nestedVerdict(_ folder: URL, relative: String, in worktree: URL, knownWorktrees: [Worktree]) async -> Verdict {
        let found = await NestedRepoFinder(git: git, search: nestedSearch)
            .find(in: folder, worktree: worktree, prefix: relative, knownWorktrees: knownWorktrees)
        let blocking = (found.worktrees + found.others.filter { $0.verdict != .clean }.map(\.path)).uniqued().sorted()
        if !blocking.isEmpty { return Verdict(reason: .nestedCheckout(blocking)) }
        if let why = found.incomplete { return Verdict(reason: .nestedSearchIncomplete(why)) }
        let clean = found.others.map(\.path)
        return Verdict(reason: nil, packageClones: (found.copies + clean).sorted())
    }
}
