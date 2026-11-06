import CleanCore
import Foundation

/// The `auto` output. Sections run skipped -> local work -> remove -> totals, so the end of the output
/// (what `tail` shows) is what would actually be removed.
struct AutoPlanText {
    let plan: AutoPlan
    let settings: Settings
    let paths: PathDisplay
    let now: Date

    func render() -> String {
        var lines: [String] = [modeLine, rulesLine, ""]

        lines.append("SKIPPED (\(plan.skipped.count)):")
        lines += indented(plan.skipped.map { skipped in
            [paths.string(skipped.row.worktree.url), idle(skipped.row), skipped.reason.label]
        })

        lines.append("")
        lines.append("LOCAL WORK, notify only (\(plan.notifyLocalWork.count)):")
        lines += indented(plan.notifyLocalWork.map { row in
            let work = row.safety.autoBlockers.filter(\.isLocalWork).map(\.label).joined(separator: ", ")
            return [paths.string(row.worktree.url), idle(row), size(row), work]
        })

        lines.append("")
        lines.append("REMOVE (\(plan.remove.count), ~\(ByteFormatting.string(plan.estimatedBytes)) estimated):")
        lines += indented(plan.remove.map { row in
            let kept = row.worktree.branch.map { "keeps branch \($0)" } ?? "detached, keeps nothing extra"
            return [paths.string(row.worktree.url), idle(row), size(row), kept]
        })

        lines.append("")
        lines.append("Totals: \(plan.remove.count) to remove (~\(ByteFormatting.string(plan.estimatedBytes)), "
            + "freed space is measured and can be lower), \(plan.notifyLocalWork.count) to notify, "
            + "\(plan.skipped.count) skipped.")
        if plan.reportOnly {
            lines.append("Report-only: a scheduled run would remove nothing yet.")
        }
        return lines.joined(separator: "\n")
    }

    func render(_ outcome: AutoRunner.Outcome) -> String {
        var lines = [""]
        for result in outcome.removed {
            let freed = result.freedBytes.map(ByteFormatting.string) ?? "unknown"
            lines.append("removed \(paths.string(result.entry.path)): freed \(freed); log id \(result.entry.id.uuidString)")
            result.warnings.forEach { lines.append("  warning: \($0)") }
        }
        for failure in outcome.failed {
            lines.append("failed \(paths.string(failure.worktree.url)): \(failure.reason)")
        }
        lines.append("Removed \(outcome.removed.count), failed \(outcome.failed.count), freed "
            + "\(ByteFormatting.string(outcome.freedBytes)) (measured), \(outcome.notified.count) with local work kept.")
        return lines.joined(separator: "\n")
    }

    private var modeLine: String {
        guard settings.autoEnabled else {
            return "Auto mode: off (settings). This is what it would do."
        }
        let since = settings.autoEnabledAt.map { " since \(DateText.short($0))" } ?? ""
        if plan.reportOnly {
            let until = plan.reportOnlyEndsAt.map { " until \(DateText.short($0))" } ?? ""
            return "Auto mode: on\(since), report-only\(until)."
        }
        return "Auto mode: on\(since)."
    }

    private var rulesLine: String {
        "Idle threshold: \(settings.idleThresholdDays) days. Claude worktrees: "
            + (settings.includeClaudeInAuto ? "included." : "skipped (setting off).")
    }

    private func idle(_ row: WorktreeAssessment) -> String {
        row.idle.idleDays.map { "idle \($0)d" } ?? "idle ?"
    }

    private func size(_ row: WorktreeAssessment) -> String {
        row.estimatedBytes.map(ByteFormatting.string) ?? "-"
    }

    private func indented(_ rows: [[String]]) -> [String] {
        guard !rows.isEmpty else { return ["  (none)"] }
        return TextTable.lines(rows).map { "  " + $0 }
    }
}
