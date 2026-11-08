import Foundation

/// Runs an `AutoPlan` through `Remover` in auto mode, one worktree at a time. Each removal carries a
/// `RemovalExpectation` built from the assessment the plan used, so a worktree that changed between the
/// plan and its turn (a new file, a new commit, another branch, now in use) is refused, not removed. A
/// refusal or failure is recorded and the run goes on with the next one.
public struct AutoRunner: Sendable {
    public var remover: Remover

    public init(remover: Remover) {
        self.remover = remover
    }

    /// Left alone by the last check before its removal; nothing was removed.
    public struct Refusal: Sendable, Hashable {
        public var worktree: Worktree
        public var reason: String
    }

    /// `git worktree remove` or something unexpected went wrong.
    public struct Failure: Sendable, Hashable {
        public var worktree: Worktree
        public var reason: String
    }

    public struct Outcome: Sendable, Hashable {
        public var removed: [RemovalResult]
        public var refused: [Refusal]
        public var failed: [Failure]
        /// Measured, summed over the removals.
        public var freedBytes: Int64
        /// Worktrees kept because they hold local work: the user should hear about them.
        public var notified: [WorktreeAssessment]
        /// Nothing was removed because the plan was report-only.
        public var reportOnly: Bool
        /// The plan's `remove` list: what a report-only run would have removed.
        public var planned: Int
        /// The `du` estimate of `planned`.
        public var estimatedBytes: Int64

        public func summary(date: Date) -> AutoRunSummary {
            AutoRunSummary(
                date: date,
                reportOnly: reportOnly,
                removedCount: removed.count,
                freedBytes: freedBytes,
                notifiedCount: notified.count,
                failures: failed.map { "\($0.worktree.path): \($0.reason)" },
                refused: refused.map { "\($0.worktree.path): \($0.reason)" },
                plannedCount: planned,
                estimatedBytes: estimatedBytes
            )
        }
    }

    /// Removes the plan's `remove` list. In report-only mode it removes nothing and never calls the
    /// remover, unless `ignoringReportOnly` (a person asked for this run). `knownWorktrees`: every worktree
    /// of the scan the plan came from, for the nested-checkout re-check. `shouldContinue` is asked before
    /// each removal; once it says no, the rest are refused untouched.
    public func run(
        _ plan: AutoPlan,
        ignoringReportOnly: Bool = false,
        knownWorktrees: [Worktree] = [],
        shouldContinue: @Sendable () async -> Bool = { true }
    ) async -> Outcome {
        var outcome = Outcome(
            removed: [], refused: [], failed: [], freedBytes: 0, notified: plan.notifyLocalWork, reportOnly: false,
            planned: plan.remove.count, estimatedBytes: plan.estimatedBytes
        )
        if plan.reportOnly && !ignoringReportOnly {
            outcome.reportOnly = true
            return outcome
        }
        var stopped = false
        for row in plan.remove {
            if !stopped, !(await shouldContinue()) { stopped = true }
            if stopped {
                outcome.refused.append(Refusal(worktree: row.worktree, reason: "the run was stopped before its turn"))
                continue
            }
            do {
                let result = try await remover.remove(
                    row.worktree,
                    mode: .auto,
                    estimatedBytes: row.estimatedBytes,
                    knownWorktrees: knownWorktrees,
                    expectation: RemovalExpectation(assessment: row)
                )
                outcome.removed.append(result)
                outcome.freedBytes += result.freedBytes ?? 0
            } catch let mismatch as RemovalExpectation.Mismatch {
                let reason = "changed since the plan: " + mismatch.changes.joined(separator: " ")
                outcome.refused.append(Refusal(worktree: row.worktree, reason: reason))
            } catch let error as RemovalError {
                switch error {
                case .refused, .notRegistered:
                    outcome.refused.append(Refusal(worktree: row.worktree, reason: "\(error)"))
                case .gitFailed:
                    outcome.failed.append(Failure(worktree: row.worktree, reason: "\(error)"))
                }
            } catch {
                outcome.failed.append(Failure(worktree: row.worktree, reason: "\(error)"))
            }
        }
        return outcome
    }
}
