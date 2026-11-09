import CleanCore
import Foundation

extension ProjectsModel {
    /// The log was read again: the projects that new entries name (a light clean in them, their removal, or the
    /// removal of a worktree of a listed main checkout) are looked at again, whoever cleaned them: the Worktrees
    /// screen, auto mode, or the CLI (seen on the app's next scan). The Overview row follows the report.
    func logReloaded() {
        let entries = app.logEntries
        guard entries.count >= logSeen else {
            // The log was replaced; nothing to compare with.
            logSeen = entries.count
            return
        }
        let fresh = entries[logSeen...]
        logSeen = entries.count
        guard report != nil, !fresh.isEmpty else { return }
        let paths = projects(namedBy: Array(fresh))
        guard !paths.isEmpty else { return }
        if isFinishingClean {
            namedByLog.formUnion(paths)
            return
        }
        Task { await rescan(paths) }
    }

    /// The listed projects a log entry is about: its path is the project, inside it or around it; for a removed
    /// worktree, also its repo's main checkout (whose idle days and processes count its linked worktrees).
    func projects(namedBy entries: [RemovalLogEntry]) -> Set<String> {
        let listed = report?.projects.map(\.worktree) ?? []
        var paths: Set<String> = []
        for entry in entries {
            for worktree in listed {
                let path = worktree.path
                let named = entry.path == path || entry.path.hasPrefix(path + "/") || path.hasPrefix(entry.path + "/")
                let mainOfRemoved = entry.action.isWorktreeRemoval && worktree.isMain && worktree.repoPath == entry.repoPath
                if named || mainOfRemoved { paths.insert(path) }
            }
        }
        return paths
    }
}
