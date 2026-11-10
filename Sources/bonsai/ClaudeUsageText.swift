import CleanCore
import Foundation

/// The `claude-usage` report as text.
struct ClaudeUsageText {
    let report: ClaudeUsageReport
    let homeDirectory: URL

    func render() -> String {
        var lines = ["Claude data: \(ByteFormatting.string(report.totalBytes)) in total. Bonsai only reads these folders.", ""]

        let transcripts = report.transcripts
        lines.append("Transcripts: \(ByteFormatting.string(transcripts.totalBytes)) in \(transcripts.projectCount) project folders")
        lines += projectLines()

        lines += ["", "File history: \(ByteFormatting.string(report.fileHistoryBytes))"]

        let versions = report.versions
        lines.append("Claude Code versions: \(ByteFormatting.string(versions.totalBytes)) in \(versions.count) installed")
        if !versions.names.isEmpty {
            lines.append("  " + versions.names.joined(separator: ", "))
        }

        lines += ["", "Claude desktop app: \(ByteFormatting.string(report.desktop.totalBytes))"]
        lines += report.desktop.largestChildren.map { child in
            "  \(sized(child.bytes))  \(child.name)"
        }

        lines += ["", "To free this space, use Claude > Settings > This computer > Storage."]
        return lines.joined(separator: "\n")
    }

    private func projectLines() -> [String] {
        guard !report.transcripts.largest.isEmpty else { return [] }
        var lines = ["  largest project folders:"]
        for project in report.transcripts.largest {
            var label: String
            if let path = project.decodedPath {
                label = HomePath.abbreviate(path, home: homeDirectory)
            } else {
                label = project.folderName
            }
            if project.folderIsGone {
                label += "  (folder gone)"
            } else if project.decodedPath == nil {
                label += "  (path not recognized)"
            }
            lines.append("  \(sized(project.bytes))  \(label)")
        }
        return lines
    }

    /// Right-aligned so the sizes line up.
    private func sized(_ bytes: Int64) -> String {
        let text = ByteFormatting.string(bytes)
        return String(repeating: " ", count: max(0, 10 - text.count)) + text
    }
}
