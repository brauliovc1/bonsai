import CleanCore
import Foundation

/// What the Simulators sheet asks the user to confirm: the exact command and the unavailable devices it
/// deletes, as listed when the sheet opened. The command takes no argument that limits it, so the model
/// looks again right before running and refuses unless it would delete exactly these devices.
public struct SimulatorsConfirmation: Identifiable, Sendable {
    /// The command as shown to the user.
    public static let command = "xcrun simctl delete unavailable"
    public static let keepsLine = "Installed runtimes and every device that can still boot are kept."

    public let id = UUID()
    public let report: SimulatorReport
    /// With the xcrun binary's full path, as `SimulatorCleaner` runs it; nil when there is no Xcode.
    public let commandLine: String?

    public init(report: SimulatorReport, commandLine: String?) {
        self.report = report
        self.commandLine = commandLine
    }

    public var devices: [SimulatorDevice] { report.unavailableDevices }
    public var estimatedBytes: Int64 { report.unavailableDevicesBytes }

    /// Why the command can't run (no Xcode), or that there is nothing to delete; nil when it can run.
    public var blocker: String? {
        guard report.state == .available else {
            return "Xcode isn't installed (xcode-select -p fails), so simulators can't be looked at or cleaned."
        }
        if let failure = report.deviceListFailure {
            return "The devices could not be listed (\(failure)), so nothing can be deleted."
        }
        return devices.isEmpty ? "No unavailable devices: nothing to delete." : nil
    }

    public var isAllowed: Bool { blocker == nil }
    public var title: String { CleanupPresentation.title("Delete", count: devices.count, noun: "simulator", bytes: estimatedBytes) }
    public var buttonTitle: String { CleanupPresentation.button("Delete", count: devices.count) }

}
