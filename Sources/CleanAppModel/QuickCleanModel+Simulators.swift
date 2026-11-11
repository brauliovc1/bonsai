import CleanCore
import Foundation

extension QuickCleanModel {
    func protectedSimulatorDelete(_ devices: [SimulatorDevice], estimatedBytes: Int64, paths: [String],
                                  fence: QuickCleanSourceFence) async -> CleanupItemResult {
        let original = dockerSimulators.runner
        let runner = CommandRunner { executable, arguments, timeout in
            if arguments == ["simctl", "delete", "unavailable"], let reason = await fence.freshReason(paths: paths) {
                throw SourceRefusal(reason: reason)
            }
            return try await original.run(executable, arguments, timeout: timeout)
        }
        guard let cleaner = SimulatorCleaner(environment: app.environment, runner: runner) else {
            return CleanupItemResult(.refused, detail: "There is no Xcode to clean simulators.")
        }
        do {
            guard let result = try await cleaner.run(ifConfirmed: true, estimatedBytes: estimatedBytes, onlyDeleting: devices) else {
                return CleanupItemResult(.refused, detail: "The simulator cleanup was not confirmed.")
            }
            return CleanupItemResult(CleanupCommandReport(kind: .simulatorsDelete, command: SimulatorsConfirmation.command, result: result, error: nil))
        } catch { return CleanupItemResult(.refused, detail: "Simulators were left alone: \(error)") }
    }

    private struct SourceRefusal: Error, Sendable, CustomStringConvertible {
        let reason: String
        var description: String { reason }
    }
}
