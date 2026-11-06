/// One worktree with its idle report and safety verdict, as of one scan.
public struct WorktreeAssessment: Sendable, Hashable, Identifiable {
    public var worktree: Worktree
    /// Not computed for main checkouts (they are never removed): `IdleReport.unknown`.
    public var idle: IdleReport
    public var safety: SafetyReport
    /// `du` estimate from the scan, when sizes were measured.
    public var estimatedBytes: Int64?

    public init(worktree: Worktree, idle: IdleReport, safety: SafetyReport, estimatedBytes: Int64? = nil) {
        self.worktree = worktree
        self.idle = idle
        self.safety = safety
        self.estimatedBytes = estimatedBytes
    }

    public var id: String { worktree.id }
    public var status: WorktreeStatus { safety.status }
}
