import Foundation

/// Runs an `AutoPlan` through `Remover` in auto mode, one worktree at a time. Each removal is re-checked
/// by the remover; a failure is recorded and the run goes on.
public struct AutoRunner: Sendable {
    public var remover: Remover

    public init(remover: Remover) {
        self.remover = remover
    }

    public struct Failure: Sendable, Hashable {
        public var worktree: Worktree
        public var reason: String
    }

    public struct Outcome: Sendable, Hashable {
        public var removed: [RemovalResult]
        public var failed: [Failure]
        /// Measured, summed over the removals.
        public var freedBytes: Int64
        /// Worktrees kept because they hold local work: the user should hear about them.
        public var notified: [WorktreeAssessment]
        /// Nothing was removed because the plan was report-only.
        public var reportOnly: Bool

        public func summary(date: Date) -> AutoRunSummary {
            AutoRunSummary(
                date: date,
                reportOnly: reportOnly,
                removedCount: removed.count,
                freedBytes: freedBytes,
                notifiedCount: notified.count,
                failures: failed.map { "\($0.worktree.path): \($0.reason)" }
            )
        }
    }

    /// Removes the plan's `remove` list. In report-only mode it removes nothing, unless
    /// `ignoringReportOnly` (a person asked for this run). `knownWorktrees`: every worktree of the scan the
    /// plan came from, for the nested-checkout re-check.
    public func run(_ plan: AutoPlan, ignoringReportOnly: Bool = false, knownWorktrees: [Worktree] = []) async -> Outcome {
        var outcome = Outcome(removed: [], failed: [], freedBytes: 0, notified: plan.notifyLocalWork, reportOnly: false)
        if plan.reportOnly && !ignoringReportOnly {
            outcome.reportOnly = true
            return outcome
        }
        for row in plan.remove {
            do {
                let result = try await remover.remove(
                    row.worktree,
                    mode: .auto,
                    estimatedBytes: row.estimatedBytes,
                    knownWorktrees: knownWorktrees
                )
                outcome.removed.append(result)
                outcome.freedBytes += result.freedBytes ?? 0
            } catch {
                outcome.failed.append(Failure(worktree: row.worktree, reason: "\(error)"))
            }
        }
        return outcome
    }
}
