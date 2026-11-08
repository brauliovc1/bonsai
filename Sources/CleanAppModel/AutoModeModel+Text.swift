import CleanCore
import Foundation

/// What the Settings tab, the Overview row and the menu say about auto mode.
extension AutoModeModel {
    /// "Auto mode: off", "Auto mode: report-only until 15 Nov 2026 at 10:00", "Auto mode: on".
    public var statusText: String {
        guard isEnabled else { return "Auto mode: off" }
        if isReportOnly {
            return "Auto mode: report-only" + (reportOnlyEndsAt.map { " until \(Self.dateText($0))" } ?? "")
        }
        return "Auto mode: on"
    }

    /// "Report-only until <date>: it lists what it would remove and deletes nothing." while in the window.
    public var reportOnlyText: String? {
        guard isReportOnly else { return nil }
        let until = reportOnlyEndsAt.map { " until \(Self.dateText($0))" } ?? ""
        return "Report-only\(until): auto mode lists what it would remove and deletes nothing."
    }

    /// What the last run did, in one line.
    public var lastRunText: String {
        guard let run = lastRun else { return "Last run: never." }
        return "Last run: \(Self.dateText(run.date)), " + Self.describe(run)
    }

    /// The worktrees the last run left alone or could not remove, with why; one line each.
    public var lastRunDetails: [String] {
        guard let run = lastRun else { return [] }
        return run.refused.map { "Left alone: \($0)" } + run.failures.map { "Failed: \($0)" }
    }

    /// When the next run may start. No closing period after a date: some locales end the time with one.
    public var nextRunText: String {
        guard isEnabled else { return "Next run: none while auto mode is off." }
        if isRunning { return "Running now…" }
        guard let next = nextRun, next > now else {
            return "Next run: at the next check (daily, at launch and when the Mac wakes)."
        }
        return "Next run: after \(Self.dateText(next))"
    }

    public static let idleThresholdNote = "Change it in General."
    /// Under "Include Claude worktrees" (PLAN §4.1, exact copy).
    public static let claudeWarning = SafetyReason.claudeSessionWarning

    /// "report only: would remove 2 worktrees (about 1.2 GB), 1 with local work."
    static func describe(_ run: AutoRunSummary) -> String {
        var parts: [String] = []
        if run.reportOnly {
            parts.append(run.plannedCount > 0
                ? "report only: would remove \(DisplayText.worktrees(run.plannedCount)) "
                    + "(about \(ByteFormatting.string(run.estimatedBytes)))"
                : "report only: nothing to remove")
        } else {
            parts.append(run.removedCount > 0
                ? "removed \(DisplayText.worktrees(run.removedCount)), freed \(ByteFormatting.string(run.freedBytes))"
                : "removed nothing")
        }
        if run.notifiedCount > 0 { parts.append("\(run.notifiedCount) with local work") }
        if !run.refused.isEmpty { parts.append("\(run.refused.count) left alone") }
        if !run.failures.isEmpty { parts.append("\(run.failures.count) failed") }
        return parts.joined(separator: ", ") + "."
    }

    static func dateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
