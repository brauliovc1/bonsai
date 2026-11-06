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
        let state: WorktreeState
        if worktree.isMain || worktree.isBare {
            state = WorktreeState()
        } else if worktree.isPrunable {
            // Only whether the folder exists matters; git commands inside it can't be trusted.
            state = Remover.itemExists(at: worktree.path) ? WorktreeState() : .missing
        } else {
            state = await inspector.inspect(worktree, knownWorktrees: knownWorktrees)
        }
        return Self.evaluate(worktree: worktree, state: state, idle: idle, settings: settings, cwdIndex: cwdIndex)
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

        // Any git error blocks both: the other facts can't be trusted.
        if let error = state.gitErrors.first { blockers.append(.gitError(error)) }
        if let reason = worktree.lockedReason { blockers.append(.locked(reason: reason)) }
        if state.changedFiles > 0 { blockers.append(.uncommitted(count: state.changedFiles)) }
        if state.localOnlyCommits > 0 {
            let reason = SafetyReason.localOnlyCommits(count: state.localOnlyCommits, onBranch: !worktree.isDetached)
            if worktree.isDetached {
                blockers.append(reason)
            } else {
                notes.append(reason)
                autoOnly.append(reason)
            }
        }
        if state.hasSubmodules { blockers.append(.submodules) }
        if !state.nestedCheckouts.isEmpty { blockers.append(.nestedCheckouts(state.nestedCheckouts)) }

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
            if days < settings.idleThresholdDays {
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
