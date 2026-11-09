import Foundation

/// Runs the idle clock and the safety check over the worktrees of a scan: one lsof for the whole batch,
/// at most `maxConcurrent` worktrees at a time. Read-only.
public struct WorktreeAssessor: Sendable {
    public var git: Git
    public var settings: Settings
    public var idleClock: IdleClock
    public var safetyCheck: SafetyCheck
    public var lsof: URL?
    public var maxConcurrent: Int

    public init(
        git: Git,
        settings: Settings,
        environment: CleanEnvironment,
        maxEntries: Int = FileActivityWalk.defaultMaxEntries,
        maxConcurrent: Int = 4
    ) {
        self.git = git
        self.settings = settings
        self.idleClock = IdleClock(
            git: git,
            claudeConfigDirectory: environment.claudeConfigDirectory,
            maxEntries: maxEntries,
            now: environment.now
        )
        self.safetyCheck = SafetyCheck(git: git)
        self.lsof = environment.tools.lsof
        self.maxConcurrent = maxConcurrent
    }

    /// The git the environment resolved, or nil when it is missing.
    public static func git(for environment: CleanEnvironment) -> Git? {
        environment.tools.git.map { Git(executable: $0) }
    }

    /// Assesses every worktree of a scan. `cwdIndex` defaults to a fresh lsof run.
    public func assess(_ scan: ScanResult, cwdIndex: ProcessCwdIndex? = nil) async -> [WorktreeAssessment] {
        await assess(scan.worktrees, sizes: scan.sizes, cwdIndex: cwdIndex)
    }

    /// `knownWorktrees`: every worktree of the scan, for spotting nested checkouts (default: `worktrees`).
    public func assess(
        _ worktrees: [Worktree],
        knownWorktrees: [Worktree]? = nil,
        sizes: [String: Int64] = [:],
        cwdIndex: ProcessCwdIndex? = nil
    ) async -> [WorktreeAssessment] {
        let index = if let cwdIndex { cwdIndex } else { await ProcessCwdIndex.capture(lsof: lsof) }
        let known = knownWorktrees ?? worktrees
        return await BoundedConcurrency.map(worktrees, limit: maxConcurrent) { worktree in
            await assess(worktree, knownWorktrees: known, cwdIndex: index, estimatedBytes: sizes[worktree.path])
        }
    }

    public func assess(
        _ worktree: Worktree,
        knownWorktrees: [Worktree],
        cwdIndex: ProcessCwdIndex,
        estimatedBytes: Int64? = nil
    ) async -> WorktreeAssessment {
        let idle = worktree.isMain || worktree.isBare ? IdleReport.unknown : await idleClock.report(for: worktree)
        let state = await safetyCheck.state(of: worktree, knownWorktrees: knownWorktrees)
        let safety = SafetyCheck.evaluate(worktree: worktree, state: state, idle: idle, settings: settings, cwdIndex: cwdIndex)
        return WorktreeAssessment(
            worktree: worktree,
            idle: idle,
            safety: safety,
            estimatedBytes: estimatedBytes,
            removeAnyway: RemoveAnyway.verdict(for: worktree, state: state, safety: safety),
            changedPaths: state.changedPaths
        )
    }
}
