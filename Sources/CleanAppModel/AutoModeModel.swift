import CleanCore
import Foundation
import Observation

/// Auto mode (PLAN decision 4): once a day, worktrees idle past the threshold that pass every auto rule
/// (§4.1) are removed; for the first `reportOnlyDays` after it is turned on it only reports. Worktrees with
/// local work only get a notification.
///
/// The scheduled check, the launch and wake checks and Run now share one path (AutoModeModel+Run): a fresh
/// scan with `WorktreeAssessor`'s verdicts, `AutoPlanner`, `AutoRunner` (each removal through `Remover` in
/// auto mode with the `RemovalExpectation` its planned assessment gives, and the rules re-read from disk
/// right before git; report-only never calls the remover), then `lastAutoRun` and at most one
/// notification. The run holds `AppModel`'s cleanup guard and `cleanup.lock` from the scan to its last
/// removal, so it never overlaps a manual cleanup, another app instance or the CLI. Settings are changed
/// the `SettingsModel` way under `settings.lock`: read the file, change only this model's keys, save, reload.
@MainActor
@Observable
public final class AutoModeModel {
    public let app: AppModel
    let notifier: any Notifier
    let appName: String
    public internal(set) var isRunning = false
    /// Why the last change or run didn't go through; nil when it did.
    public internal(set) var error: String?
    /// Turned off here during a run: the run stops before git runs for its next removal.
    var stopRequested = false
    /// After every run that got as far as a plan (the menu bar refreshes its free space).
    var onRunFinished: (@MainActor () async -> Void)?
    /// Test seam: runs after the plan is made, before the first removal, inside the cleanup guard.
    var afterPlanning: @MainActor () async -> Void = {}

    public init(app: AppModel, notifier: any Notifier = SilentNotifier(), appName: String = "Bonsai") {
        self.app = app
        self.notifier = notifier
        self.appName = appName
        app.reloadSettings()
        repairMissingStartDate()
    }

    var settings: Settings { app.settings }
    var now: Date { app.environment.now() }

    public var isEnabled: Bool { settings.autoEnabled }
    public var includesClaudeWorktrees: Bool { settings.includeClaudeInAuto }
    /// Read-only here; General edits it.
    public var idleThresholdDays: Int { settings.idleThresholdDays }
    public var reportOnlyEndsAt: Date? { AutoSchedule.reportOnlyEndsAt(settings) }
    /// On and inside the report-only window.
    public var isReportOnly: Bool { isEnabled && AutoSchedule.isReportOnly(now: now, settings: settings) }
    public var lastRun: AutoRunSummary? { settings.lastAutoRun }
    public var nextRun: Date? { AutoSchedule.nextRun(now: now, settings: settings) }
    public var canRunNow: Bool { isEnabled && !isRunning && !app.isCleaningUp && !app.isQuitting }

    // MARK: - Settings

    /// Turns auto mode on and starts the report-only window now (turning it off and on again restarts the
    /// window), then asks for notification permission: here, never at launch. Already on: nothing changes.
    public func enable() async {
        do {
            let saved = try SettingsEditor.current(app)
            if saved.autoEnabled && saved.autoEnabledAt != nil {
                app.reloadSettings()
                return
            }
            let start = now
            try SettingsEditor.update(app) { settings in
                settings.autoEnabled = true
                settings.autoEnabledAt = start
            }
            error = nil
        } catch {
            self.error = "Auto clean was not turned on: \(error)"
            return
        }
        _ = await notifier.requestAuthorization()
    }

    /// Turns auto mode off. A run that is going stops before git runs for its next removal.
    public func disable() {
        stopRequested = true
        save("Auto clean was not turned off") { $0.autoEnabled = false }
    }

    /// Includes or skips Claude-app worktrees, then scans again (the statuses use it).
    public func setIncludesClaudeWorktrees(_ include: Bool) async {
        guard save("The setting was not saved", { $0.includeClaudeInAuto = include }) else { return }
        await app.refresh()
    }

    /// On with no start date (written by hand or by an older version) would stay report-only forever and
    /// never have asked for notifications: the report-only week starts now, and permission is asked, as if it
    /// had just been turned on.
    func repairMissingStartDate() {
        guard let saved = try? SettingsEditor.current(app), saved.autoEnabled, saved.autoEnabledAt == nil else { return }
        let start = now
        do {
            try SettingsEditor.update(app) { settings in
                if settings.autoEnabled && settings.autoEnabledAt == nil { settings.autoEnabledAt = start }
            }
        } catch {
            self.error = "Auto clean has no start date and it could not be set: \(error)"
            return
        }
        Task { _ = await notifier.requestAuthorization() }
    }

    @discardableResult
    func save(_ failure: String, _ change: (inout Settings) -> Void) -> Bool {
        do {
            try SettingsEditor.update(app, change)
            error = nil
            return true
        } catch {
            self.error = "\(failure): \(error)"
            return false
        }
    }
}
