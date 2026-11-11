import CleanCore
import Foundation

/// What the Docker sheet asks the user to confirm: the exact command, what it removes and keeps, and the
/// state of the daemon when the sheet looked. `DockerCleaner` runs it only for Docker Desktop with a
/// running daemon (`DockerReport.pruneBlocker`), and the model looks again right before running.
public struct DockerPruneConfirmation: Identifiable, Sendable {
    /// The command as shown to the user.
    public static let command = "docker system prune -f"
    public static let removes = [
        "Stopped containers",
        "Networks no container uses",
        "Dangling images (untagged ones nothing uses)",
        "Build cache nothing uses",
    ]
    public static let keeps = [
        "Volumes (no --volumes)",
        "Tagged images (no -a)",
        "Running containers",
    ]
    public static let slowLine = "Docker Desktop can take a while to give the space back."

    public let id = UUID()
    /// What the sheet found when it opened.
    public let report: DockerReport
    /// With the docker binary's full path, as `DockerCleaner` runs it; nil when docker isn't installed.
    public let commandLine: String?

    public init(report: DockerReport, commandLine: String?) {
        self.report = report
        self.commandLine = commandLine
    }

    /// Why the prune can't run now (not installed, not running, not Docker Desktop); nil when it can.
    public var blocker: String? { report.pruneBlocker }
    public var isAllowed: Bool { blocker == nil }
    /// The most the prune can free (`docker system df` reclaimable, without volumes): an upper bound.
    public var estimatedBytes: Int64 { report.pruneCeilingBytes }
    public var hasSizeEstimate: Bool { report.state == .running && report.usageFailure == nil }
    public var estimatedSizeText: String { hasSizeEstimate ? "up to \(DisplayText.bytes(estimatedBytes))" : "size unknown" }
    public var usage: [DockerUsageLine] { report.usage.map(DockerUsageLine.init) }
    public var title: String { "Clean up Docker (\(estimatedSizeText))?" }
    public var buttonTitle: String { "Clean up Docker" }

}
