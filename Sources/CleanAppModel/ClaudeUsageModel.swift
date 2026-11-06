import CleanCore
import Foundation
import Observation

/// The Claude usage screen: where Claude's own data takes disk space, from `ClaudeUsageReport`. Read-only:
/// the model exposes `refresh()` and nothing else that acts, and there is no delete in `ClaudeUsageScanner`
/// either. A test fails if a delete, move or write call appears in this model or its view.
@MainActor
@Observable
public final class ClaudeUsageModel {
    /// Fixed copy of the screen.
    public static let note = "Clean these from Claude > Settings > This computer > Storage. "
        + "Bonsai never deletes Claude's data."

    public let app: AppModel
    @ObservationIgnored private let loop = ScanLoop()

    public private(set) var report: ClaudeUsageReport?
    public private(set) var isScanning = false
    public private(set) var lastScanAt: Date?

    public init(app: AppModel) {
        self.app = app
    }

    // MARK: - What the screen shows

    public var totalText: String { DisplayText.bytes(report?.totalBytes) }

    /// Transcripts, file history, Claude Code versions and the desktop app's data, each with its size.
    public var summaryLines: [ClaudeSizeLine] {
        guard let report else { return [] }
        let projects = report.transcripts.projectCount
        return [
            ClaudeSizeLine(
                title: "Transcripts",
                detail: "\(projects) \(projects == 1 ? "project folder" : "project folders")",
                bytes: report.transcripts.totalBytes
            ),
            ClaudeSizeLine(title: "File history", detail: nil, bytes: report.fileHistoryBytes),
            ClaudeSizeLine(
                title: "Claude Code versions",
                detail: "\(report.versions.count) installed",
                bytes: report.versions.totalBytes
            ),
            ClaudeSizeLine(title: "Claude desktop app data", detail: nil, bytes: report.desktop.totalBytes),
        ]
    }

    /// The biggest transcript folders, largest first.
    public var transcriptRows: [ClaudeTranscriptRow] {
        (report?.transcripts.largest ?? []).map(ClaudeTranscriptRow.init)
    }

    /// Installed Claude Code versions, oldest first.
    public var versionNames: [String] { report?.versions.names ?? [] }

    /// The desktop app's largest children, largest first.
    public var desktopRows: [ClaudeSizeLine] {
        (report?.desktop.largestChildren ?? []).map { ClaudeSizeLine(title: $0.name, detail: nil, bytes: $0.bytes) }
    }

    public var warnings: [String] { report?.warnings ?? [] }

    // MARK: - Scanning

    /// Measures Claude's folders now, or once more after the running scan; returns when that scan is done.
    public func refresh() async {
        await loop.run { [self] in
            isScanning = true
            report = await ClaudeUsageScanner(environment: app.environment).scan(using: app.scan)
            lastScanAt = app.environment.now()
            isScanning = false
        }
    }
}
