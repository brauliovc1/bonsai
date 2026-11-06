import CleanCore
import Foundation

/// `scan --json`: the scan result (worktrees filtered by `--status`) plus one verdict per worktree.
struct ScanJSON: Encodable {
    struct Verdict: Encodable {
        var path: String
        var status: String
        var group: String
        var idleDays: Int?
        var newestSignal: String?
        var manualAllowed: Bool
        var autoEligible: Bool
        var blockers: [String]
        var notes: [String]
        var autoBlockers: [String]
    }

    var scan: ScanResult
    var verdicts: [Verdict]

    init(scan: ScanResult, assessments: [WorktreeAssessment]) {
        var filtered = scan
        let shown = Set(assessments.map(\.worktree.path))
        filtered.worktrees = scan.worktrees.filter { shown.contains($0.path) }
        self.scan = filtered
        self.verdicts = assessments.map { assessment in
            Verdict(
                path: assessment.worktree.path,
                status: assessment.status.label,
                group: assessment.status.group,
                idleDays: assessment.idle.idleDays,
                newestSignal: assessment.idle.newestSignal?.rawValue,
                manualAllowed: assessment.safety.manualAllowed,
                autoEligible: assessment.safety.autoEligible,
                blockers: assessment.safety.blockers.map(\.label),
                notes: assessment.safety.notes.map(\.label),
                autoBlockers: assessment.safety.autoBlockers.map(\.label)
            )
        }
    }

    func encoded() throws -> String {
        String(decoding: try CleanJSON.encoder().encode(self), as: UTF8.self)
    }
}
