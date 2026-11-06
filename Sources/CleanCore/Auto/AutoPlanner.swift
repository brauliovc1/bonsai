import Foundation

/// Groups assessed worktrees into an `AutoPlan`. Pure.
///
/// `SafetyReport.autoEligible` already reflects every auto rule; the planner re-checks the idle threshold,
/// the Claude setting and main checkouts anyway, so a report computed with other settings can't slip
/// through.
public enum AutoPlanner {
    public static func plan(_ rows: [WorktreeAssessment], settings: Settings, now: Date) -> AutoPlan {
        var plan = AutoPlan(reportOnly: settings.isReportOnly(now: now), reportOnlyEndsAt: settings.reportOnlyEndsAt)

        for row in rows {
            let worktree = row.worktree
            if worktree.isMain || worktree.isBare { continue }
            if worktree.kind == .claude && !settings.includeClaudeInAuto {
                plan.skipped.append(.init(row: row, reason: .claudeSession))
                continue
            }

            let days = row.idle.idleDays
            let idleEnough = days.map { $0 >= max(1, settings.idleThresholdDays) } ?? false
            if row.safety.autoEligible && idleEnough {
                plan.remove.append(row)
                continue
            }
            if idleEnough && holdsLocalWork(row.safety) {
                plan.notifyLocalWork.append(row)
                continue
            }
            plan.skipped.append(.init(row: row, reason: skipReason(row, idleEnough: idleEnough)))
        }
        return plan
    }

    /// Kept only because of local work: not because it is gone, locked, broken or a main checkout.
    static func holdsLocalWork(_ safety: SafetyReport) -> Bool {
        let hardStop = safety.blockers.contains { reason in
            switch reason {
            case .mainCheckout, .missingFolder, .locked, .gitError: true
            default: false
            }
        }
        return !hardStop && safety.autoBlockers.contains(where: \.isLocalWork)
    }

    private static func skipReason(_ row: WorktreeAssessment, idleEnough: Bool) -> SafetyReason {
        if let first = row.safety.autoBlockers.first { return first }
        if !idleEnough, let days = row.idle.idleDays { return .recentlyActive(days: days) }
        return .idleUnknown
    }
}
