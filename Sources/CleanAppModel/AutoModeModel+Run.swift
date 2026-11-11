import CleanCore
import Foundation

/// The one path every auto-mode run takes.
extension AutoModeModel {
    /// The launch, wake and hourly check: runs when `AutoSchedule.shouldRun` says so (on, and at least 24 h
    /// since the last run), with the settings read now. It is asked again under the cleanup lock, so another
    /// app instance that just ran makes this one skip.
    public func checkSchedule() async {
        guard !isRunning, !app.isQuitting else { return }
        repairMissingStartDate()
        guard let settings = try? SettingsEditor.current(app),
              AutoSchedule.shouldRun(now: now, settings: settings) else { return }
        _ = await run(onlyIfDue: true)
    }

    /// Runs auto mode now, on the same path as the scheduled run (report-only inside the window). Does
    /// nothing while a run is going or when auto mode is off; when another cleanup (here, in another app
    /// instance or in the CLI) holds the lock it doesn't start and the next check tries again. Returns what
    /// was saved as `lastAutoRun`, nil when nothing ran.
    @discardableResult
    public func runNow() async -> AutoRunSummary? {
        await run(onlyIfDue: false)
    }

    private enum RunResult {
        case ran(AutoRunner.Outcome, AutoRunSummary)
        case notDue
        case problem(String)
    }

    private func run(onlyIfDue: Bool) async -> AutoRunSummary? {
        await app.cleanupQueue.waitUntilEmpty()
        guard !isRunning, !app.isQuitting else { return nil }
        isRunning = true
        defer { isRunning = false }
        stopRequested = false
        repairMissingStartDate()
        do {
            guard try SettingsEditor.current(app).autoEnabled else {
                error = "Auto clean is off."
                return nil
            }
        } catch {
            self.error = "Auto clean didn't run: \(error)"
            return nil
        }
        let finished = await app.cleaningUp(byAutoMode: true) { () -> RunResult in
            let result = await planAndRun(onlyIfDue: onlyIfDue)
            // Saved while the lock is still held, so another instance's due check sees this run.
            if case .ran(_, let summary) = result { record(summary) }
            return result
        }
        guard let result = finished else {
            error = "Auto clean waited: \(app.busyReason). The next check tries again."
            return nil
        }
        switch result {
        case .notDue:
            return nil
        case .problem(let problem):
            error = "Auto clean didn't run: \(problem)"
            return nil
        case .ran(let outcome, let summary):
            await finish(outcome, summary: summary)
            return summary
        }
    }

    private func record(_ summary: AutoRunSummary) {
        do {
            try SettingsEditor.update(app) { $0.lastAutoRun = summary }
            error = nil
        } catch {
            self.error = "The run was not recorded: \(error)"
        }
    }

    /// Refreshes and notifies, after the lock is released.
    private func finish(_ outcome: AutoRunner.Outcome, summary: AutoRunSummary) async {
        if outcome.removed.isEmpty || app.isQuitting {
            app.reloadLog()
            app.disk.refresh()
        } else {
            await app.cleanupFinished()
        }
        // Nobody wants to hear from auto mode after turning it off, nor from an app that is quitting.
        let stillOn = !stopRequested && (try? SettingsEditor.current(app))?.autoEnabled == true
        if stillOn, !app.isQuitting, let content = NotificationContent.autoRun(summary, appName: appName) {
            await notifier.post(content)
        }
        await onRunFinished?()
    }

    /// Scan, plan, run. Inside the cleanup guard and `cleanup.lock`. `started` is the summary's date.
    private func planAndRun(onlyIfDue: Bool) async -> RunResult {
        let started = now
        // Under the lock: another instance may have run since the check outside it.
        if onlyIfDue {
            guard let saved = try? SettingsEditor.current(app), AutoSchedule.shouldRun(now: now, settings: saved) else {
                return .notDue
            }
        }
        await app.refresh()
        if let problem = app.problem { return .problem(problem) }
        guard let scan = app.scan, let git = app.git else { return .problem("nothing was scanned") }
        // The settings the scan read: its verdicts were made with them.
        let settings = app.settings
        guard settings.autoEnabled else { return .problem("auto clean was turned off") }
        let plan = AutoPlanner.plan(app.assessments, settings: settings, now: now)
        await afterPlanning()
        let remover = Remover(git: git, settings: settings, environment: app.environment)
        let outcome = await AutoRunner(remover: remover).run(plan, knownWorktrees: scan.worktrees) { [weak self] in
            // nil = go on; a model that is gone stops the run.
            guard let self else { return .turnedOff }
            return await stopReason(planned: settings)
        }
        return .ran(outcome, outcome.summary(date: started))
    }

    /// Asked before each removal and inside `Remover` right before git runs: nil to go on. Stops when the
    /// app is quitting, auto mode was turned off (here or on disk), or the saved rules are no longer the ones
    /// the plan used (Claude setting, threshold, report-only window). The settings are re-read from disk
    /// under `settings.lock`; a file that can't be read stops the run.
    func stopReason(planned: Settings) -> RemovalStop? {
        if app.isQuitting { return .quitting }
        if stopRequested { return .turnedOff }
        guard let saved = try? SettingsEditor.current(app) else { return .rulesChanged }
        guard saved.autoEnabled else { return .turnedOff }
        let sameRules = saved.includeClaudeInAuto == planned.includeClaudeInAuto
            && saved.effectiveIdleThresholdDays == planned.effectiveIdleThresholdDays
            && !AutoSchedule.isReportOnly(now: now, settings: saved)
        return sameRules ? nil : .rulesChanged
    }
}
