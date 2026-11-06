import Foundation

/// The PLAN §4.2 light-clean conditions for one folder, plus the nested-checkout rule of §4.1 (added
/// 11-06). `LightCleanFinder` runs it for every folder whose name matched, and `LightCleaner` runs it
/// again right before deleting each candidate. Read-only.
///
/// git always runs inside the folder with `.`, never with the folder's path as an argument: Foundation's
/// `Process` hands arguments to git decomposed ("é" as "e" + U+0301), and git can't match a decomposed
/// path that contains an emoji against the worktree it is in.
struct LightCleanCheck: Sendable {
    var git: Git
    var nestedSearch: NestedCheckoutSearch

    struct Verdict: Sendable, Hashable {
        /// nil = the folder may be deleted.
        var reason: LightCleanSkipReason?
        /// Clones with no local work inside, which go with the folder.
        var packageClones: [String] = []
    }

    /// `relative`: the folder, relative to `worktree`. `knownWorktrees`: every registered worktree of
    /// every scanned repo; one inside the folder keeps it.
    func verdict(for relative: String, in worktree: URL, knownWorktrees: [Worktree]) async -> Verdict {
        // Every folder on the way down must be a plain folder: a symlinked parent would aim the delete elsewhere.
        var parent = ""
        for part in relative.split(separator: "/").dropLast() {
            parent = parent.isEmpty ? String(part) : parent + "/" + part
            guard DirectoryEntries.kind(ofItemAt: worktree.appending(path: parent).path) == .directory else {
                return Verdict(reason: .notACandidate("\(parent) is not a plain folder"))
            }
        }
        let folder = worktree.appending(path: relative, directoryHint: .isDirectory)
        switch DirectoryEntries.kind(ofItemAt: folder.path) {
        case .symlink: return Verdict(reason: .symlink)
        case .other, nil: return Verdict(reason: .gone)
        case .directory: break
        }
        if Remover.itemExists(at: folder.appending(path: ".git").path) {
            return Verdict(reason: .nestedCheckout(["."]))
        }
        if let reason = await gitReason(folder, worktree: worktree) { return Verdict(reason: reason) }
        return await nestedVerdict(folder, knownWorktrees: knownWorktrees)
    }

    /// Tracking nothing and ignored, as git sees it from inside the folder. A git failure is a reason too.
    /// Tracked files are asked first: git calls a folder with tracked files in it "not ignored".
    private func gitReason(_ folder: URL, worktree: URL) async -> LightCleanSkipReason? {
        do {
            // git must answer for this worktree, not for a repo around it (a broken `.git` file).
            let topLevel = try await git.gitString(["rev-parse", "--show-toplevel"], in: folder)
            guard CanonicalPath.same(URL(fileURLWithPath: topLevel), worktree) else {
                return .gitError("git sees \(topLevel) here, not this worktree")
            }
            if !(try await git.git(["ls-files", "-z"], in: folder)).isEmpty { return .hasTrackedFiles }
            let ignore = try await git.result(["check-ignore", "-q", "."], in: folder)
            if ignore.timedOut { return .gitError("git check-ignore timed out") }
            switch ignore.exitCode {
            case 0: break
            case 1: return .notIgnored
            default:
                let message = ignore.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return .gitError("git check-ignore failed (exit \(ignore.exitCode))" + (message.isEmpty ? "" : ": \(message)"))
            }
            return nil
        } catch {
            return .gitError("\(error)")
        }
    }

    /// `.git` files and registered worktrees always keep the folder; a plain clone keeps it unless it
    /// holds no local work (P2's `NestedCloneCheck`). A search that can't finish keeps it too.
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
