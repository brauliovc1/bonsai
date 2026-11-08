import Foundation

/// Runs an `AutoPlan` through `Remover` in auto mode, one worktree at a time. Each removal carries a
/// `RemovalExpectation` built from the assessment the plan used, so a worktree that changed between the
/// plan and its turn (a new file, a new commit, another branch, now in use) is refused, not removed. A
/// refusal or failure is recorded and the run goes on with the next one; a stop ends the run.
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
        /// Why the run stopped early, if it did.
        public var stopped: RemovalStop?
        /// The worktrees not removed because the run stopped (never touched, never logged).
        public var stoppedWorktrees: [Worktree] = []

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
                estimatedBytes: estimatedBytes,
                stopReason: stopped,
                stoppedCount: stoppedWorktrees.count
            )
        }
    }

    /// Removes the plan's `remove` list. In report-only mode it removes nothing and never calls the
    /// remover, unless `ignoringReportOnly` (a person asked for this run). `knownWorktrees`: every worktree
    /// of the scan the plan came from, for the nested-checkout re-check. `stopReason` is asked before each
    /// removal and again inside `Remover`, right before git runs; once it gives a reason, the run stops and
    /// the rest are left untouched.
    public func run(
        _ plan: AutoPlan,
        ignoringReportOnly: Bool = false,
        knownWorktrees: [Worktree] = [],
        stopReason: @escaping @Sendable () async -> RemovalStop? = { nil }
    ) async -> Outcome {
        var outcome = Outcome(
            removed: [], refused: [], failed: [], freedBytes: 0, notified: plan.notifyLocalWork, reportOnly: false,
            planned: plan.remove.count, estimatedBytes: plan.estimatedBytes
        )
        if plan.reportOnly && !ignoringReportOnly {
            outcome.reportOnly = true
            return outcome
        }
        for (index, row) in plan.remove.enumerated() {
            if let stop = await stopReason() {
                outcome.stop(stop, leaving: plan.remove[index...])
                break
            }
            do {
                let result = try await remover.remove(
                    row.worktree,
                    mode: .auto,
                    estimatedBytes: row.estimatedBytes,
                    knownWorktrees: knownWorktrees,
                    expectation: RemovalExpectation(assessment: row),
                    stillAllowed: stopReason
                )
                outcome.removed.append(result)
                outcome.freedBytes += result.freedBytes ?? 0
            } catch let mismatch as RemovalExpectation.Mismatch {
                let reason = "changed since the plan: " + mismatch.changes.joined(separator: " ")
                outcome.refused.append(Refusal(worktree: row.worktree, reason: reason))
            } catch let error as RemovalError {
                switch error {
                case .stopped(let stop):
                    outcome.stop(stop, leaving: plan.remove[index...])
                case .refused, .notRegistered:
                    outcome.refused.append(Refusal(worktree: row.worktree, reason: "\(error)"))
                case .gitFailed, .interrupted:
                    outcome.failed.append(Failure(worktree: row.worktree, reason: "\(error)"))
                }
                if outcome.stopped != nil { break }
            } catch {
                outcome.failed.append(Failure(worktree: row.worktree, reason: "\(error)"))
            }
        }
        return outcome
    }
}

extension AutoRunner.Outcome {
    mutating func stop(_ reason: RemovalStop, leaving rows: ArraySlice<WorktreeAssessment>) {
        stopped = reason
        stoppedWorktrees = rows.map(\.worktree)
    }
}
