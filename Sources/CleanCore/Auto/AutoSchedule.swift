import Foundation

/// When auto mode runs, and whether a run only reports. Pure: the app's daily check, launch check and wake
/// check all ask these.
public enum AutoSchedule {
    /// At most one run per this many seconds (a day).
    public static let interval: TimeInterval = 86_400
    /// The background activity asks every hour (10 minutes tolerance), so a run starts within about an hour
    /// of being due, and never sooner than `interval` after the last one.
    public static let checkInterval: TimeInterval = 3_600
    public static let checkTolerance: TimeInterval = 600
    /// After a wake the check waits this long: right after waking a Mac can be too busy for timed work.
    public static let wakeDelay: Duration = .seconds(5 * 60)

    /// True when auto mode is on and has not run in the last 24 hours. A last run dated after `now` (the
    /// clock was set back) counts as old; otherwise auto mode would wait until that date.
    public static func shouldRun(now: Date, settings: Settings) -> Bool {
        guard settings.autoEnabled else { return false }
        guard let last = settings.lastAutoRun?.date, last <= now else { return true }
        return now.timeIntervalSince(last) >= interval
    }

    /// True inside the report-only window: from `autoEnabledAt` until `reportOnlyDays` later. Without a
    /// start date it is report-only too: when in doubt, nothing is removed.
    public static func isReportOnly(now: Date, settings: Settings) -> Bool {
        settings.isReportOnly(now: now)
    }

    /// The first moment a run may remove something, or nil when auto mode has no start date.
    public static func reportOnlyEndsAt(_ settings: Settings) -> Date? {
        settings.reportOnlyEndsAt
    }

    /// The earliest moment the next run may start: `now` when one is due, nil when auto mode is off.
    public static func nextRun(now: Date, settings: Settings) -> Date? {
        guard settings.autoEnabled else { return nil }
        guard let last = settings.lastAutoRun?.date, last <= now else { return now }
        return max(now, last.addingTimeInterval(interval))
    }
}
