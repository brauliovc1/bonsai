/// One worktree with its idle report and safety verdict, as of one scan.
public struct WorktreeAssessment: Sendable, Hashable, Identifiable {
    public var worktree: Worktree
    /// Not computed for main checkouts (they are never removed): `IdleReport.unknown`.
    public var idle: IdleReport
    public var safety: SafetyReport
    /// `du` estimate from the scan, when sizes were measured.
    public var estimatedBytes: Int64?
    /// Whether "Remove anyway" (PLAN §4.8) is offered, with what it would delete; from the same inspection as
    /// `safety`. Only a hint: the confirmation and the removal each look again.
    public var removeAnyway: RemoveAnyway.Verdict

    /// `removeAnyway`: nil = from `safety` alone (never offered for a blocked worktree: nothing was listed).
    public init(
        worktree: Worktree,
        idle: IdleReport,
        safety: SafetyReport,
        estimatedBytes: Int64? = nil,
        removeAnyway: RemoveAnyway.Verdict? = nil
    ) {
        self.worktree = worktree
        self.idle = idle
        self.safety = safety
        self.estimatedBytes = estimatedBytes
        self.removeAnyway = removeAnyway ?? RemoveAnyway.verdict(for: worktree, state: nil, safety: safety)
    }

    public var id: String { worktree.id }
    public var status: WorktreeStatus { safety.status }
}
