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

    /// Runs `xcrun simctl delete unavailable` through `SimulatorCleaner`. The command takes no argument that
    /// limits it, so `SimulatorCleaner` lists the devices again right before it starts (devices only, no
    /// sizes) and runs only when the unavailable ones are exactly the devices the sheet listed; if the list
    /// changed, nothing runs. CleanCore writes the log entry; if that fails the report says so. Then the
    /// screen scans again. A second confirm while the delete runs is rejected in the return value only: the
    /// running delete's progress stays.
    @discardableResult
    public func confirmSimulatorsDelete(_ confirmation: SimulatorsConfirmation) async -> CleanupCommandReport {
        guard !isDeletingDevices else { return Self.simulatorsReport(error: "A delete is already running.", result: nil) }
        guard confirmation.isAllowed else {
            return show(Self.simulatorsReport(error: confirmation.blocker ?? "The delete is not allowed.", result: nil))
        }
        isDeletingDevices = true
        let finished = await app.cleaningUp {
            await runDelete(confirmed: confirmation.devices, estimatedBytes: confirmation.estimatedBytes)
        }
        let report = finished ?? Self.simulatorsReport(error: "Another cleanup is still running.", result: nil)
        isDeletingDevices = false
        _ = show(report)
        if finished != nil {
            await app.cleanupFinished(rescanWorktrees: false)
            await refresh()
        }
        return report
    }

    private func runDelete(confirmed: [SimulatorDevice], estimatedBytes: Int64) async -> CleanupCommandReport {
        guard let cleaner = SimulatorCleaner(environment: app.environment, runner: runner) else {
            return Self.simulatorsReport(error: "There is no Xcode (xcrun) to run it with.", result: nil)
        }
        do {
            guard let result = try await cleaner.run(ifConfirmed: true, estimatedBytes: estimatedBytes, onlyDeleting: confirmed) else {
                return Self.simulatorsReport(error: "The delete was not confirmed.", result: nil)
            }
            return Self.simulatorsReport(error: nil, result: result)
        } catch let refusal as SimulatorCleaner.Refusal {
            return Self.simulatorsReport(error: refusal.description, result: nil)
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
