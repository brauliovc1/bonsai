import CleanCore
import Foundation

/// `scan --json`: the scan result (worktrees filtered by `--status`) plus one verdict per worktree, with
/// the worktree's last commit and its repo's remotes (URLs without credentials).
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
        var lastCommit: CommitSummary?
        var remotes: [GitRemote]
    }

    var scan: ScanResult
    var verdicts: [Verdict]

    init(scan: ScanResult, assessments: [WorktreeAssessment]) {
        var filtered = scan
        let shown = Set(assessments.map(\.worktree.path))
        filtered.worktrees = scan.worktrees.filter { shown.contains($0.path) }
        // Each verdict carries these; not twice.
        filtered.lastCommits = nil
        filtered.remotes = nil
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
                autoBlockers: assessment.safety.autoBlockers.map(\.label),
                lastCommit: scan.lastCommit(of: assessment.worktree),
                remotes: scan.remotes(of: assessment.worktree)
            )
        }
    }

    func encoded() throws -> String {
        String(decoding: try CleanJSON.encoder().encode(self), as: UTF8.self)
    }
}
