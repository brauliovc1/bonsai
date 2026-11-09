import CleanCore
import Foundation

/// How `projects` prints its table: one row per project, biggest first, then the totals and where to go next.
struct ProjectsText {
    let report: ProjectFoldersReport
    let shown: [ProjectFolders]
    let threshold: Int
    let all: Bool
    let paths: PathDisplay

    func render() -> String {
        var lines: [String] = []
        if shown.isEmpty {
            lines.append(all ? "No project folders found." : "No project idle \(threshold)+ days has folders to delete.")
        } else {
            var rows = [["SIZE", "IDLE", "STATUS", "FOLDERS", "PROJECT"]]
            for project in shown {
                rows.append([
                    ByteFormatting.string(project.totalBytes) + (project.hasUnknownSizes ? "+" : ""),
                    project.idleDays.map { "\($0)d" } ?? "unknown",
                    project.status(threshold: threshold).label,
                    Self.folderNames(project),
                    paths.string(project.worktree.url),
                ])
            }
            lines += TextTable.lines(rows, rightAligned: [0, 1])
        }
        lines.append("")
        let idle = report.idleTotal(atLeast: threshold)
        lines.append("Idle \(threshold)+ days, nothing running inside: \(ByteFormatting.string(idle.bytes)) in \(Self.projects(idle.count))")
        lines.append("All: \(ByteFormatting.string(report.all.bytes)) in \(Self.projects(report.all.count))")
        if !all, shown.count < report.projects.count {
            lines.append("\(Self.projects(report.projects.count - shown.count)) used more recently or with idle unknown; --all shows them.")
        }
        if report.leftOut.count > 0 {
            let what = report.leftOut.count == 1 ? "1 Claude/Cursor worktree holds" : "\(report.leftOut.count) Claude/Cursor worktrees hold"
            lines.append("\(what) \(ByteFormatting.string(report.leftOut.bytes)) more; see `clean-claude scan` (remove them whole).")
        }
        lines.append("Sizes are estimates. To clean one project: clean-claude light-clean <path> --yes (without --yes it is a dry run).")
        return lines.joined(separator: "\n")
    }

    /// "node_modules, .next": each folder name once.
    static func folderNames(_ project: ProjectFolders) -> String {
        var names: [String] = []
        for folder in project.folders where !names.contains(folder.name) { names.append(folder.name) }
        return names.joined(separator: ", ")
    }

    static func projects(_ count: Int) -> String {
        count == 1 ? "1 project" : "\(count) projects"
    }
}
