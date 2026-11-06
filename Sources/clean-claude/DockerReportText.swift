import CleanCore
import Foundation

/// The `docker` command's report as text.
struct DockerReportText {
    let report: DockerReport
    let homeDirectory: URL

    func render() -> String {
        var lines: [String] = []
        switch report.state {
        case .notInstalled:
            lines.append("Docker: not installed (no docker binary in the usual places).")
        case .notRunning:
            lines.append("Docker Desktop: not running. Start Docker to clean it.")
        case .running:
            let version = report.serverVersion.map { " (server \($0))" } ?? ""
            lines.append("Docker Desktop: running\(version)")
        }

        if let image = report.diskImage {
            let path = HomePath.abbreviate(image.path, home: homeDirectory)
            lines.append("Disk image: \(ByteFormatting.string(image.allocatedBytes)) allocated  \(path)")
        } else {
            lines.append("Disk image: Docker.raw not found.")
        }

        if report.state == .running {
            lines.append("")
            lines += usageLines()
        }
        return lines.joined(separator: "\n")
    }

    private func usageLines() -> [String] {
        guard !report.usage.isEmpty else { return ["docker system df returned no rows."] }
        var rows = [["TYPE", "TOTAL", "ACTIVE", "SIZE", "RECLAIMABLE"]]
        for row in report.usage {
            rows.append([
                row.type,
                String(row.total),
                String(row.active),
                ByteFormatting.string(row.sizeBytes),
                ByteFormatting.string(row.reclaimableBytes),
            ])
        }
        return AlignedColumns.lines(rows, rightAligned: [1, 2, 3, 4])
            + ["", "Reclaimable in total: \(ByteFormatting.string(report.reclaimableBytes)) (as docker system df counts it)."]
    }
}
