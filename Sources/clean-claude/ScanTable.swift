import CleanCore
import Foundation

/// The `scan` table: REPO, BRANCH, KIND, SIZE, IDLE, STATUS, PATH, then a one-line summary.
struct ScanTable {
    let result: ScanResult
    /// The rows to show (filtered by `--status`).
    let assessments: [WorktreeAssessment]
    /// Every row, for the summary counts.
    let allAssessments: [WorktreeAssessment]
    let paths: PathDisplay
    let showSizes: Bool

    func render() -> String {
        var rows: [[String]] = [header]
        for assessment in assessments {
            let worktree = assessment.worktree
            var row = [
                worktree.repoURL.lastPathComponent,
                worktree.branch ?? (worktree.isBare ? "(bare)" : "(detached)"),
                worktree.kind.rawValue,
            ]
            if showSizes {
                row.append(result.size(of: worktree).map(ByteFormatting.string) ?? "-")
            }
            row.append(Self.idleCell(assessment))
            row.append(assessment.status.label)
            row.append(paths.string(worktree.url))
            rows.append(row)
        }
        let rightAligned: Set<Int> = showSizes ? [3, 4] : [3]
        return (TextTable.lines(rows, rightAligned: rightAligned) + [summary]).joined(separator: "\n")
    }

    private var header: [String] {
        showSizes
            ? ["REPO", "BRANCH", "KIND", "SIZE", "IDLE", "STATUS", "PATH"]
            : ["REPO", "BRANCH", "KIND", "IDLE", "STATUS", "PATH"]
    }

    /// Days, `?` when unknown, `-` for main checkouts (never removed, so not measured).
    static func idleCell(_ assessment: WorktreeAssessment) -> String {
        if assessment.worktree.isMain || assessment.worktree.isBare { return "-" }
        return assessment.idle.idleDays.map { "\($0)d" } ?? "?"
    }

    private var summary: String {
        let linked = result.worktrees.filter { !$0.isMain }.count
        var line = "\(result.worktrees.count) worktrees (\(linked) linked) in \(result.repos.count) repos"
        if showSizes {
            let total = result.sizes.values.reduce(0, +)
            line += ", \(ByteFormatting.string(total)) total (estimate)"
        }
        let groups = Dictionary(grouping: allAssessments.filter { !$0.worktree.isMain }, by: \.status.group)
            .mapValues(\.count)
        line += "; linked: \(groups["auto-ready", default: 0]) auto-ready, \(groups["safe", default: 0]) safe, "
            + "\(groups["blocked", default: 0]) blocked"
        if assessments.count != allAssessments.count {
            line += "; showing \(assessments.count)"
        }
        line += String(format: ", %.1f s", result.duration)
        return line
    }
}
