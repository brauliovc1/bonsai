import Foundation

/// The Overview's auto clean row (PLAN §8.3): "Auto clean is off · Removes finished worktrees once a day ·
/// Turn on…", "Auto clean is on, next run tonight", "Auto clean is report-only until 15 Nov".
public struct AutoCleanLine: Equatable, Sendable {
    public let title: String
    public let detail: String
    /// Opens the Settings window's auto mode tab.
    public let buttonTitle: String
    public let isRunning: Bool

    @MainActor
    public init(autoMode: AutoModeModel) {
        let now = autoMode.app.environment.now()
        isRunning = autoMode.isRunning
        guard autoMode.isEnabled else {
            title = "Auto clean is off"
            detail = "Removes finished worktrees once a day."
            buttonTitle = "Turn on…"
            return
        }
        buttonTitle = "Settings…"
        let last = autoMode.isRunning ? "Running now…" : autoMode.lastRunText
        if autoMode.isReportOnly {
            let until = autoMode.reportOnlyEndsAt.map { " until \(Self.day($0))" } ?? ""
            title = "Auto clean is report-only\(until)"
            detail = "It lists what it would remove and deletes nothing yet. \(last)"
        } else {
            title = "Auto clean is on, next run \(Self.nextRun(autoMode.nextRun, now: now))"
            detail = last
        }
    }

    /// "tonight", "today at 10:00", "tomorrow", "on 15 Nov", "at the next check".
    static func nextRun(_ next: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let next, next > now else { return "at the next check" }
        if calendar.isDate(next, inSameDayAs: now) {
            return calendar.component(.hour, from: next) >= 18 ? "tonight" : "today at \(next.formatted(date: .omitted, time: .shortened))"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(next, inSameDayAs: tomorrow) {
            return "tomorrow"
        }
        return "on \(day(next))"
    }

    /// "15 Nov".
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }
}
