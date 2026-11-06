import CleanCore
import Foundation

/// How `light-clean` prints what it found and what it did.
enum LightCleanText {
    static func findings(_ findings: LightCleanFindings, name: String) -> String {
        var lines: [String] = []
        if findings.candidates.isEmpty {
            lines.append("\(name): no folders to delete.")
        } else {
            lines.append("\(name): \(findings.candidates.count) \(findings.candidates.count == 1 ? "folder" : "folders") "
                + "to delete, about \(ByteFormatting.string(findings.estimatedBytes)) (estimate):")
            var rows = [["SIZE", "FOLDER"]]
            for candidate in findings.candidates {
                let clones = candidate.packageClones.isEmpty ? "" : "  (with \(candidate.packageClones.count) package clones)"
                rows.append([candidate.estimatedBytes.map(ByteFormatting.string) ?? "?", candidate.relativePath + clones])
            }
            lines += TextTable.lines(rows, rightAligned: [0]).map { "  " + $0 }
        }
        if !findings.skipped.isEmpty {
            lines.append("Skipped:")
            var rows = [["REASON", "FOLDER"]]
            for skip in findings.skipped {
                rows.append([skip.reason.label, skip.relativePath])
            }
            lines += TextTable.lines(rows).map { "  " + $0 }
            for skip in findings.skipped where detailed(skip.reason) {
                lines.append("  \(skip.relativePath): \(skip.reason.sentence)")
            }
        }
        for folder in findings.unreadable {
            lines.append("warning: could not read \(folder); nothing below it was looked at")
        }
        return lines.joined(separator: "\n")
    }

    static func result(_ result: LightCleanResult, name: String) -> String {
        var lines: [String] = []
        for candidate in result.deleted {
            lines.append("deleted \(candidate.relativePath)" + (candidate.estimatedBytes.map { " (estimate \(ByteFormatting.string($0)))" } ?? ""))
        }
        for skip in result.refused {
            lines.append("refused \(skip.relativePath): \(skip.reason.sentence)")
        }
        for failure in result.failed {
            lines.append("failed \(failure.candidate.relativePath): \(failure.message)")
        }
        if !result.entries.isEmpty {
            let freed = result.freedBytes.map(ByteFormatting.string) ?? "unknown"
            lines.append("\(name): \(result.deleted.count) deleted, freed \(freed) (measured); \(result.entries.count) log entries")
        } else {
            lines.append("\(name): nothing was deleted.")
        }
        return lines.joined(separator: "\n")
    }

    /// Reasons whose label leaves out what matters (which checkout, which error).
    private static func detailed(_ reason: LightCleanSkipReason) -> Bool {
        switch reason {
        case .nestedCheckout, .nestedSearchIncomplete, .gitError, .notACandidate: true
        default: false
        }
    }
}
