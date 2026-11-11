import Foundation

extension ProjectsModel {
    @discardableResult
    public func queueClean(_ confirmation: ProjectsConfirmation) -> CleanupTask? {
        let items = confirmation.cleanable.map(\.lightClean)
        let task = app.queueFolders(items, beforeFinish: {
            self.isFinishingClean = true
        }) {
            self.isFinishingClean = false
            let paths = Set(items.map(\.worktree.path)).union(self.namedByLog)
            self.namedByLog = []
            await self.rescan(paths)
        }
        if task != nil { selection.subtract(items.map { $0.worktree.path }); dismissClean() }
        return task
    }
}
