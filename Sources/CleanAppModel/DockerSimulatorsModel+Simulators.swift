import CleanCore
import Foundation

extension DockerSimulatorsModel {
    /// The Simulators sheet's content, from a scan made now: the unavailable devices the command would
    /// delete at this moment.
    public func prepareSimulatorsDelete() async -> SimulatorsConfirmation {
        let fresh = await SimulatorScanner(environment: app.environment, runner: runner).scan()
        simulators = fresh
        let commandLine = SimulatorCleaner(environment: app.environment, runner: runner)?.commandLine
        return SimulatorsConfirmation(report: fresh, commandLine: commandLine)
    }

    /// Opens the Simulators sheet and fills it once the scan is done.
    public func beginSimulatorsDelete() async {
        simulatorsSheetToken += 1
        let token = simulatorsSheetToken
        simulatorsReport = nil
        simulatorsConfirmation = nil
        isShowingSimulatorsSheet = true
        isPreparingSimulators = true
        let prepared = await prepareSimulatorsDelete()
        // Closed (or opened again) while looking: drop this result.
        guard token == simulatorsSheetToken, isShowingSimulatorsSheet else { return }
        simulatorsConfirmation = prepared
        isPreparingSimulators = false
    }

    /// Closes the sheet; not while the command runs.
    public func dismissSimulatorsDelete() {
        guard !isDeletingDevices else { return }
        simulatorsSheetToken += 1
        isShowingSimulatorsSheet = false
        isPreparingSimulators = false
        simulatorsConfirmation = nil
        simulatorsReport = nil
    }

    /// Runs `xcrun simctl delete unavailable` through `SimulatorCleaner.run(ifConfirmed:estimatedBytes:)`.
    /// The command takes no argument that limits it, so a scan made right before must find exactly the
    /// devices the sheet listed; if the list changed, nothing runs. CleanCore writes the log entry; if that
    /// fails the report says so. Then the screen scans again.
    @discardableResult
    public func confirmSimulatorsDelete(_ confirmation: SimulatorsConfirmation) async -> CleanupCommandReport {
        guard confirmation.isAllowed, !isDeletingDevices else {
            return show(Self.simulatorsReport(error: confirmation.blocker ?? "A delete is already running.", result: nil))
        }
        isDeletingDevices = true
        let finished = await app.cleaningUp { await runDelete(confirmed: confirmation.devices) }
        let report = finished ?? Self.simulatorsReport(error: "Another cleanup is still running.", result: nil)
        isDeletingDevices = false
        _ = show(report)
        if finished != nil {
            await app.cleanupFinished(rescanWorktrees: false)
            await refresh()
        }
        return report
    }

    private func runDelete(confirmed: [SimulatorDevice]) async -> CleanupCommandReport {
        let current = await SimulatorScanner(environment: app.environment, runner: runner).scan()
        simulators = current
        guard current.state == .available else {
            return Self.simulatorsReport(error: "Xcode isn't installed any more.", result: nil)
        }
        guard Set(current.unavailableDevices.map(\.udid)) == Set(confirmed.map(\.udid)) else {
            return Self.simulatorsReport(
                error: "The list of unavailable devices changed since you confirmed it, so nothing was deleted; "
                    + "review it again.",
                result: nil
            )
        }
        guard let cleaner = SimulatorCleaner(environment: app.environment, runner: runner) else {
            return Self.simulatorsReport(error: "There is no Xcode (xcrun) to run it with.", result: nil)
        }
        do {
            guard let result = try await cleaner.run(ifConfirmed: true, estimatedBytes: current.unavailableDevicesBytes) else {
                return Self.simulatorsReport(error: "The delete was not confirmed.", result: nil)
            }
            return Self.simulatorsReport(error: nil, result: result)
        } catch {
            return Self.simulatorsReport(error: "xcrun could not be started: \(error)", result: nil)
        }
    }

    private func show(_ report: CleanupCommandReport) -> CleanupCommandReport {
        simulatorsReport = report
        return report
    }

    private static func simulatorsReport(error: String?, result: CleanupCommandResult?) -> CleanupCommandReport {
        CleanupCommandReport(kind: .simulatorsDelete, command: SimulatorsConfirmation.command, result: result, error: error)
    }
}
