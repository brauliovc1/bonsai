import CleanCore
import Foundation

/// `projects --json`: the shown projects biggest first, each with its folders, the folders left alone and how to
/// get them back, plus the totals and the Claude/Cursor worktrees left out.
struct ProjectsJSON: Encodable {
    struct Folder: Encodable {
        var path: String
        var relativePath: String
        var name: String
        var bytes: Int64?
    }

    struct Skipped: Encodable {
        var relativePath: String
        var reason: String
        var sentence: String
    }

    struct Project: Encodable {
        var repo: String
        var path: String
        var kind: String
        var idleDays: Int?
        var status: String
        var statusSentence: String
        var totalBytes: Int64
        var folders: [Folder]
        var skipped: [Skipped]
        var unreadable: [String]
        var rebuild: [String]
    }

    struct Totals: Encodable {
        /// Idle at least `idleDays`, nothing running inside: what the app's "Select all idle" picks.
        var idle: ProjectFoldersReport.Total
        var all: ProjectFoldersReport.Total
        /// Claude and Cursor worktrees with light-clean folders, not listed.
        var leftOut: ProjectFoldersReport.Total
    }

    var idleDays: Int
    var filter: String
    var projects: [Project]
    var totals: Totals
    var problems: [String]

    init(report: ProjectFoldersReport, shown: [ProjectFolders], threshold: Int, all: Bool) {
        idleDays = threshold
        filter = all ? "all" : "idle"
        projects = shown.map { project in
            let status = project.status(threshold: threshold)
            return Project(
                repo: project.worktree.repoPath,
                path: project.worktree.path,
                kind: project.worktree.kind.rawValue,
                idleDays: project.idleDays,
                status: status.label,
                statusSentence: status.sentence,
                totalBytes: project.totalBytes,
                folders: project.folders.map {
                    Folder(path: $0.candidate.path, relativePath: $0.relativePath, name: $0.name, bytes: $0.bytes)
                },
                skipped: project.skipped.map {
                    Skipped(relativePath: $0.relativePath, reason: $0.reason.label, sentence: $0.reason.sentence)
                },
                unreadable: project.unreadable,
                rebuild: project.rebuildLines
            )
        }
        totals = Totals(idle: report.idleTotal(atLeast: threshold), all: report.all, leftOut: report.leftOut)
        problems = report.problems
    }

    func encoded() throws -> String {
        String(decoding: try CleanJSON.encoder().encode(self), as: UTF8.self)
    }
}
