import CleanCore
import Foundation

extension CachesModel {
    public func queueResource(_ id: String) -> String { "cache:" + id }

    @discardableResult
    public func queueClean(_ confirmation: CachesConfirmation) -> CleanupTask? {
        let items = confirmation.allowed
        let work = items.compactMap { item -> CleanupWork? in
            guard let finding = item.finding else { return nil }
            let resources = [queueResource(item.id)] + finding.paths
            return CleanupWork(CleanupItem(name: item.name, resources: resources, estimatedBytes: item.bytes)) {
                let cleaner = ToolCacheCleaner(environment: self.app.environment, processes: self.processes)
                let result = await cleaner.clean([finding])
                return CleanupItemResult(CachesCleanReport(items: [item], result: result, busy: ""))
            }
        }
        let task = app.cleanupQueue.enqueue(title: items.count == 1 ? items[0].name : "Tool caches", unit: "items", work: work) { _ in
            await self.app.cleanupFinished(rescanWorktrees: false)
            await self.refresh()
        }
        if task != nil { selection.subtract(items.map(\.id)); dismissClean() }
        return task
    }
}
