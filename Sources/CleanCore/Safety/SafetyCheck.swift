import Foundation

/// PLAN §4.1, row by row, with the manual and auto columns computed separately. It takes the idle report
/// and the settings, so `autoEligible` already reflects every auto rule.
///
/// Runs at scan time and again immediately before each removal (`Remover`). When in doubt, it blocks.
public struct SafetyCheck: Sendable {
    public var inspector: WorktreeInspector

    public init(git: Git) {
        self.inspector = WorktreeInspector(git: git)
    }

    /// Reads the worktree's state, then evaluates it.
    public func check(
        _ worktree: Worktree,
        idle: IdleReport,
        settings: Settings,
        cwdIndex: ProcessCwdIndex,
        knownWorktrees: [Worktree] = []
    ) async -> SafetyReport {
        let state = await state(of: worktree, knownWorktrees: knownWorktrees)
        return Self.evaluate(worktree: worktree, state: state, idle: idle, settings: settings, cwdIndex: cwdIndex)
    }

    /// The facts `evaluate` needs. Main checkouts are not inspected (never removed), and for a prunable
    /// entry only whether the folder exists matters: git commands inside it can't be trusted.
    public func state(of worktree: Worktree, knownWorktrees: [Worktree] = []) async -> WorktreeState {
        if worktree.isMain || worktree.isBare { return WorktreeState() }
        if worktree.isPrunable { return Remover.itemExists(at: worktree.path) ? WorktreeState() : .missing }
        return await inspector.inspect(worktree, knownWorktrees: knownWorktrees)
    }

    /// The rules themselves, over facts already gathered. Pure.
    public static func evaluate(
        worktree: Worktree,
        state: WorktreeState,
        idle: IdleReport,
        settings: Settings,
        cwdIndex: ProcessCwdIndex
    ) -> SafetyReport {
        // Main checkout: never, for both. Nothing else matters.
        if worktree.isMain || worktree.isBare {
            return SafetyReport(blockers: [.mainCheckout], notes: [], autoBlockers: [.mainCheckout])
        }
        // Folder missing: prune instead, never auto.
        if !state.folderExists {
            var blockers: [SafetyReason] = [.missingFolder]
            if let reason = worktree.lockedReason { blockers.append(.locked(reason: reason)) }
            return SafetyReport(blockers: blockers, notes: [], autoBlockers: blockers)
        }
        // git calls it prunable although the folder is there: its `.git` file is gone or broken, and git
        // commands run inside would describe some other repo. Nothing else can be trusted.
        if let reason = worktree.prunableReason {
            let message = "git marks it prunable (\(reason.isEmpty ? "no reason given" : reason)) but the folder "
                + "exists; its .git file is missing or broken"
            return SafetyReport(blockers: [.gitError(message)], notes: [], autoBlockers: [.gitError(message)])
        }

        var blockers: [SafetyReason] = []
        var notes: [SafetyReason] = []
        var autoOnly: [SafetyReason] = []

        // A stale record or any git error blocks both: the other facts can't be trusted.
        if let leadsTo = state.staleRecord { blockers.append(.staleRecord(leadsTo: leadsTo)) }
        if let error = state.gitErrors.first { blockers.append(.gitError(error)) }
        if let reason = worktree.lockedReason { blockers.append(.locked(reason: reason)) }
        if !state.operationsInProgress.isEmpty { blockers.append(.operationInProgress(state.operationsInProgress)) }
        if state.changedFiles > 0 { blockers.append(.uncommitted(count: state.changedFiles)) }
        if !state.hiddenEdits.isEmpty { blockers.append(.hiddenLocalEdits(state.hiddenEdits)) }
        if state.localOnlyCommits > 0 {
            let reason = SafetyReason.localOnlyCommits(count: state.localOnlyCommits, onBranch: !worktree.isDetached)
            if worktree.isDetached {
                blockers.append(reason)
            } else {
                notes.append(reason)
                autoOnly.append(reason)
            }
        }
        if state.reflogOnlyCommits > 0 { blockers.append(.reflogOnlyCommits(count: state.reflogOnlyCommits)) }
        if state.hasSubmodules { blockers.append(.submodules) }
        if !state.nestedCheckouts.isEmpty { blockers.append(.nestedCheckouts(state.nestedCheckouts)) }
        if !state.nestedClones.isEmpty { notes.append(.nestedClones(state.nestedClones)) }
        if let why = state.nestedSearchIncomplete {
            notes.append(.nestedSearchIncomplete(why))
            autoOnly.append(.nestedSearchIncomplete(why))
        }

        if cwdIndex.isAvailable {
            let processes = cwdIndex.processes(inside: worktree.url)
            if !processes.isEmpty { blockers.append(.inUse(processes)) }
        } else {
            notes.append(.inUseUnknown)
            autoOnly.append(.inUseUnknown)
        }

        if state.branchStashes > 0 {
            notes.append(.stash(count: state.branchStashes))
            autoOnly.append(.stash(count: state.branchStashes))
        }
        if !state.ignoredUserFiles.isEmpty {
            notes.append(.ignoredUserFiles(state.ignoredUserFiles))
            autoOnly.append(.ignoredUserFiles(state.ignoredUserFiles))
        }
        if worktree.kind == .claude {
            notes.append(.claudeSession)
            if !settings.includeClaudeInAuto { autoOnly.append(.claudeSession) }
        }

        if let days = idle.idleDays {
            if days < max(1, settings.idleThresholdDays) {
                notes.append(.recentlyActive(days: days))
                autoOnly.append(.recentlyActive(days: days))
            }
        } else {
            notes.append(.idleUnknown)
            autoOnly.append(.idleUnknown)
        }

        return SafetyReport(blockers: blockers, notes: notes, autoBlockers: blockers + autoOnly)
    }
}
