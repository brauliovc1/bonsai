import CleanCore
import Foundation

/// The second page of the Docker and Simulators sheets: what the one command did, or why it did not run.
public struct CleanupCommandReport: Sendable {
    public enum Kind: Sendable { case dockerPrune, simulatorsDelete }

    public let kind: Kind
    /// The command as shown.
    public let command: String
    /// nil when the command did not run.
    public let result: CleanupCommandResult?
    /// Why it did not run (blocked, changed since the sheet listed it, could not start, another cleanup).
    public let error: String?

    init(kind: Kind, command: String, result: CleanupCommandResult?, error: String?) {
        self.kind = kind
        self.command = command
        self.result = result
        self.error = error
    }

    public var didRun: Bool { result != nil }
    public var succeeded: Bool { result?.succeeded == true }
    public var output: String { result?.output ?? "" }
    public var freedBytes: Int64? { result?.freedBytes }
    /// Docker's own "Total reclaimed space" (inside its disk image).
    public var reportedBytes: Int64? { result?.reportedBytes }
    /// The command ran but its log entry could not be written: shown as an error, never swallowed.
    public var logError: String? { result?.logError }

    public var summary: String {
        if let error { return "Nothing was run. \(error)" }
        guard let result else { return "Nothing was run." }
        if result.timedOut { return "The command timed out." }
        if result.exitCode != 0 { return "The command failed (exit \(result.exitCode))." }
        let freed = DisplayText.bytes(result.freedBytes)
        switch kind {
        case .dockerPrune:
            var text = "Pruned. This disk gained \(freed) (measured)."
            if let reported = result.reportedBytes {
                text += " Docker reports \(DisplayText.bytes(reported)) reclaimed inside its disk image."
            }
            return text + " " + DockerPruneConfirmation.slowLine
        case .simulatorsDelete:
            return "Deleted the unavailable simulator devices. This disk gained \(freed) (measured)."
        }
    }
    public var headline: String { CleanupPresentation.headline(freedBytes) }

}
