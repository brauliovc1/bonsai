import Foundation

/// PLAN §4.8 "Remove anyway": by hand, one worktree, after the person saw the exact loss list.
extension Remover {
    /// Removes one blocked worktree with `git -C <repo> worktree remove --force <path>` (exactly one `--force`;
    /// the branch is kept), logged as `worktreeRemoveAnyway` with the loss list in its notes.
    ///
    /// Right before git runs, the whole §4.1 inspection runs again (the process index last) and the loss list is
    /// built again from it; then the fast, volatile facts are read once more (`lastMomentChanges`), immediately
    /// before git. Nothing is deleted, and `RemovalExpectation.Mismatch` is thrown ("It changed since you
    /// confirmed"), when anything differs from what was confirmed: a blocker Remove anyway never overrides, any
    /// entry of the list (a new or changed path, another count, a new repo or category), git's record of the
    /// worktree (branch, HEAD, kind), a new note, or activity since. There is no auto mode here and no
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
        // The inspection above takes seconds on a real worktree; what changes fastest is read once more, now.
        let late = await lastMomentChanges(fresh, confirmed: confirmed)
        guard late.isEmpty else { throw RemovalExpectation.Mismatch(path: fresh.path, changes: late) }

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

    /// The checks that are fast and change fastest, after the slow inspection and the process index (PLAN §4.8, P12b
    /// review: a rebase and a file started during the slow part were deleted): an operation in progress, `git status`
    /// path by path, hidden edits, the files of uninitialized submodule folders, and the stamp of every listed path.
    /// Each sentence is a difference from `confirmed`; empty when there is none.
    func lastMomentChanges(_ worktree: Worktree, confirmed: LossList) async -> [String] {
        let folder = worktree.url
        do {
            let gitDir = URL(fileURLWithPath: try await git.gitString(["rev-parse", "--absolute-git-dir"], in: folder))
            if let marker = WorktreeInspector.operationsInProgress(gitDir: gitDir).first {
                return ["New: \(marker) in its git dir (an operation started)."]
            }
            let status = GitStatusEntry.parse(
                try await git.git(["status", "--porcelain=v1", "-z", "--untracked-files=all"], in: folder)
            )
            let hidden = try await WorktreeInspector(git: git).hiddenEdits(in: folder)
            let submodules = confirmed.entries(.submodules).map(\.text).filter { $0 != ".gitmodules" }
            let walk = SubmoduleFolderWalk.files(in: folder, submodules: submodules)
            if let incomplete = walk.incomplete { return ["Everything in \(incomplete) could no longer be listed."] }
            let ignored = confirmed.entries(.ignoredFiles).map(\.text)
            let stamps = WorktreeInspector.stamps(of: status.map(\.path) + hidden + walk.files + ignored, in: folder)
            let now = LossList(sections: [
                LossList.Section(category: .uncommittedFiles, entries: RemoveAnyway.uncommittedEntries(status, stamps: stamps)),
                LossList.Section(category: .hiddenEdits, entries: RemoveAnyway.pathEntries(hidden, stamps: stamps)),
                LossList.Section(category: .submoduleFiles, entries: RemoveAnyway.pathEntries(walk.files, stamps: stamps)),
                LossList.Section(category: .ignoredFiles, entries: RemoveAnyway.pathEntries(ignored, stamps: stamps)),
            ])
            let checked: Set<LossList.Category> = [.uncommittedFiles, .hiddenEdits, .submoduleFiles, .ignoredFiles]
            let then = LossList(sections: confirmed.sections.filter { checked.contains($0.category) })
            return now.changes(since: then)
        } catch {
            return ["git couldn't be asked once more: \(error)"]
        }
    }
}
