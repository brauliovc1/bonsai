import Foundation

/// PLAN §4.8 "Remove anyway": by hand, one worktree, after the person saw the exact loss list.
extension Remover {
    /// Removes one blocked worktree with `git -C <repo> worktree remove --force <path>` (exactly one `--force`;
    /// the branch is kept), logged as `worktreeRemoveAnyway` with the loss list in its notes.
    ///
    /// Right before git runs, the whole §4.1 inspection runs again (the process index last) and the loss list is
    /// built again from it. Nothing is deleted, and `RemovalExpectation.Mismatch` is thrown ("It changed since
    /// you confirmed"), when anything differs from what was confirmed: a blocker Remove anyway never overrides,
    /// any entry of the list (a new or changed path, another count, a new repo or category), git's record of
    /// the worktree (branch, HEAD, kind), a new note, or activity since. There is no auto mode here and no
    /// `stillAllowed`: the caller is a person, holding the cleanup guard and `cleanup.lock`.
    public func removeAnyway(
        _ worktree: Worktree,
        confirmed: LossList,
        expectation: RemovalExpectation,
        estimatedBytes: Int64?,
        knownWorktrees: [Worktree] = []
    ) async throws -> RemovalResult {
        let (fresh, siblings) = try await reread(worktree, mode: .manual)
        let idle = fresh.isMain || fresh.isBare ? IdleReport.unknown : await assessor.idleClock.report(for: fresh)
        let state = await assessor.safetyCheck.state(of: fresh, knownWorktrees: knownWorktrees + siblings)
        await afterInspection()
        let safety = SafetyCheck.evaluate(
            worktree: fresh,
            state: state,
            idle: idle,
            settings: assessor.settings,
            cwdIndex: await captureCwdIndex()
        )

        var changes = expectation.changes(fresh: fresh, safety: safety, idle: idle)
        switch RemoveAnyway.verdict(for: fresh, state: state, safety: safety) {
        case .offered(let list):
            changes += list.changes(since: confirmed)
        case .notNeeded:
            changes.append("Nothing stops a plain removal now; remove it the usual way.")
        case .unavailable(let reason):
            changes.append("New: \(reason.sentence)")
        }
        guard changes.isEmpty else { throw RemovalExpectation.Mismatch(path: fresh.path, changes: changes) }

        return try await removeAndLog(
            fresh,
            mode: .manual,
            action: .worktreeRemoveAnyway,
            safety: safety,
            notes: confirmed.logNotes,
            estimatedBytes: estimatedBytes,
            stillAllowed: nil
        )
    }
}
