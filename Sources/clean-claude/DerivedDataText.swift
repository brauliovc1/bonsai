import CleanCore
import Foundation

/// How `derived-data` prints the report and a deletion.
struct DerivedDataText {
    let report: DerivedDataReport
    let home: URL

    func render() -> String {
        let root = HomePath.abbreviate(report.root, home: home)
        guard report.rootExists else { return "\(root) does not exist: Xcode has no DerivedData here." }
        guard !report.entries.isEmpty else { return "\(root) is empty." }

        // Orphaned first (what can be deleted), then by size.
        let order = Dictionary(uniqueKeysWithValues: DerivedDataState.allCases.enumerated().map { ($1, $0) })
        let sorted = report.entries.sorted { lhs, rhs in
            if lhs.state != rhs.state { return order[lhs.state, default: 0] < order[rhs.state, default: 0] }
            return (lhs.bytes ?? 0) > (rhs.bytes ?? 0)
        }
        var rows = [["STATE", "SIZE", "FOLDER", "PROJECT"]]
        for entry in sorted {
            let project = entry.workspacePath.map { HomePath.abbreviate($0, home: home) } ?? "-"
            rows.append([
                entry.state.label,
                entry.bytes.map(ByteFormatting.string) ?? "?",
                entry.name,
                project + (entry.detail.map { "  (\($0))" } ?? ""),
            ])
        }
        let counts = DerivedDataState.allCases.compactMap { state -> String? in
            let entries = report.entries(in: state)
            guard !entries.isEmpty else { return nil }
            return "\(entries.count) \(state.label) (\(ByteFormatting.string(report.bytes(in: state))))"
        }
        let summary = "\(report.entries.count) entries in \(root), \(ByteFormatting.string(report.totalBytes)) "
            + "(estimate): " + counts.joined(separator: ", ")
        return (TextTable.lines(rows, rightAligned: [1]) + [summary]).joined(separator: "\n")
    }

    static func deletion(_ deletion: DerivedDataDeletion) -> String {
        var lines: [String] = []
        for orphan in deletion.deleted {
            lines.append("deleted \(orphan.name)" + (orphan.bytes.map { " (estimate \(ByteFormatting.string($0)))" } ?? ""))
        }
        for refusal in deletion.refused {
            lines.append("refused \(refusal.orphan.name): \(refusal.reason)")
        }
        for failure in deletion.failed {
            lines.append("failed \(failure.orphan.name): \(failure.message)")
        }
        if let entry = deletion.entry {
            let freed = deletion.freedBytes.map(ByteFormatting.string) ?? "unknown"
            lines.append("\(deletion.deleted.count) deleted, freed \(freed) (measured); log id \(entry.id.uuidString)")
        } else {
            lines.append("Nothing was deleted.")
        }
        return lines.joined(separator: "\n")
    }
}
