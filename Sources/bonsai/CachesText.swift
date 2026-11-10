import CleanCore
import Foundation

/// How `caches` prints the report, what `caches clean` would do, and what it did.
struct CachesText {
    let report: ToolCacheReport
    let home: URL

    func render() -> String {
        var lines: [String] = []
        for section in ToolCacheEntry.Section.allCases {
            let findings = report.findings(in: section)
            if !lines.isEmpty { lines.append("") }
            lines.append(section.title)
            if section == .cursor, report.cursorRunning {
                lines.append("Cursor is running: quit it to clean its data.")
            }
            guard !findings.isEmpty else {
                lines.append("  none on this Mac")
                continue
            }
            var rows = [["ID", "SIZE", "STATUS", "FOLDER"]]
            for finding in findings {
                rows.append([finding.id, finding.bytes.map(ByteFormatting.string) ?? "?", status(finding), folders(finding)])
            }
            lines += TextTable.lines(rows, rightAligned: [1])
        }
        let ready = report.ready
        lines.append("")
        lines.append("\(ready.count) \(ready.count == 1 ? "entry" : "entries") ready to clean, "
            + "\(ByteFormatting.string(report.readyBytes)) (estimate). Clean with: bonsai caches clean <entry-id>… --yes")
        return lines.joined(separator: "\n")
    }

    /// One line per named entry for `caches clean`: what would go, or why it stays.
    func plan(_ finding: ToolCacheFinding) -> String {
        let size = finding.bytes.map { "about \(ByteFormatting.string($0)) (estimate)" } ?? "size unknown"
        switch finding.verdict {
        case .ready:
            var what = "the contents of " + folders(finding)
            if case .cursorAgentVersions = finding.entry.deletion {
                let names = finding.removals.map { ($0 as NSString).lastPathComponent }
                what = "\(names.count) old \(names.count == 1 ? "version" : "versions") (" + names.joined(separator: ", ") + ")"
            } else if case .cursorStateBackup = finding.entry.deletion {
                what = folders(finding)
            }
            var line = "\(finding.id): would clean \(what), \(size). \(finding.note)"
            if !finding.kept.isEmpty {
                line += " Keeps " + finding.kept.map { "\($0.name) (\($0.reason))" }.joined(separator: ", ") + "."
            }
            return line
        case .empty:
            return "\(finding.id): nothing to clean in " + folders(finding)
        case .refused(let why):
            return "\(finding.id): left alone: \(why)"
        case .displayOnly(let why):
            return "\(finding.id): shown only (\(why))"
        }
    }

    private func status(_ finding: ToolCacheFinding) -> String {
        switch finding.verdict {
        case .ready:
            finding.kept.isEmpty ? "ready" : "ready (keeps " + finding.kept.map(\.name).joined(separator: ", ") + ")"
        case .empty: "empty"
        case .refused(let why): "refused: \(why)"
        case .displayOnly(let why): "shown only: \(why)"
        }
    }

    private func folders(_ finding: ToolCacheFinding) -> String {
        finding.paths.map { HomePath.abbreviate($0, home: home) }.joined(separator: ", ")
    }

    static func result(_ result: ToolCacheCleanResult, home: URL) -> String {
        var lines: [String] = []
        for cleaned in result.cleaned {
            let freed = cleaned.freedBytes.map(ByteFormatting.string) ?? "unknown"
            let estimate = cleaned.estimatedBytes.map { "; estimate \(ByteFormatting.string($0))" } ?? ""
            lines.append("cleaned \(cleaned.id): removed \(cleaned.removedCount) "
                + "\(cleaned.removedCount == 1 ? "item" : "items"), freed \(freed) (measured\(estimate))")
            lines += cleaned.failures.map { "  could not remove \($0)" }
        }
        for refusal in result.refused {
            lines.append("refused \(refusal.id): \(refusal.reason)")
        }
        if result.entries.isEmpty {
            lines.append("Nothing was cleaned.")
        } else {
            let freed = result.freedBytes.map(ByteFormatting.string) ?? "unknown"
            lines.append("\(result.cleaned.count) cleaned, freed \(freed) (measured); \(result.entries.count) log "
                + "\(result.entries.count == 1 ? "entry" : "entries")")
        }
        return lines.joined(separator: "\n")
    }
}
