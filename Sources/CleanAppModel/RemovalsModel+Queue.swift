import CleanCore
import Foundation

extension RemovalsModel {
    @discardableResult
    public func queueRestore(_ id: RemovalLogRow.ID) -> CleanupTask? {
        guard let row = rows.first(where: { $0.id == id }), row.isRestorable, let git = app.git else { return nil }
        let item = CleanupItem(name: row.path, resources: [row.path])
        return app.cleanupQueue.enqueue(title: "Restore worktree", unit: "worktrees", work: [CleanupWork(item) {
            let message = await Self.restore(id, with: Restorer(git: git, environment: self.app.environment))
            return CleanupItemResult(message.isError ? .failed : .cleaned, detail: message.text)
        }]) { _ in
            await self.app.cleanupFinished()
        }
    }
}
