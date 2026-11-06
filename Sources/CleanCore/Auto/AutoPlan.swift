import Foundation

/// What auto mode would do with the worktrees of one scan. Main checkouts never appear.
public struct AutoPlan: Sendable, Hashable {
    public struct Skipped: Sendable, Hashable {
        public var row: WorktreeAssessment
        /// The first reason auto mode leaves it alone.
        public var reason: SafetyReason

        public init(row: WorktreeAssessment, reason: SafetyReason) {
            self.row = row
            self.reason = reason
        }
    }

    /// Idle past the threshold and auto-eligible.
    public var remove: [WorktreeAssessment]
    /// Idle past the threshold but holding local work (uncommitted files, local-only commits, a stash,
    /// ignored user files): the user gets a notification instead.
    public var notifyLocalWork: [WorktreeAssessment]
    public var skipped: [Skipped]
    /// Inside the report-only window: a scheduled run removes nothing.
    public var reportOnly: Bool
    public var reportOnlyEndsAt: Date?

    public init(
        remove: [WorktreeAssessment] = [],
        notifyLocalWork: [WorktreeAssessment] = [],
        skipped: [Skipped] = [],
        reportOnly: Bool,
        reportOnlyEndsAt: Date? = nil
    ) {
        self.remove = remove
        self.notifyLocalWork = notifyLocalWork
        self.skipped = skipped
        self.reportOnly = reportOnly
        self.reportOnlyEndsAt = reportOnlyEndsAt
    }

    /// Sum of the `du` estimates of `remove` (missing estimates count as 0). Freed space is measured
    /// after removal and can be lower.
    public var estimatedBytes: Int64 {
        remove.compactMap(\.estimatedBytes).reduce(0, +)
    }
}
