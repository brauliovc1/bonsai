import CleanCore
import Foundation

extension DerivedDataModel {
    @discardableResult
    public func queueDelete(_ confirmation: DerivedDataConfirmation) -> CleanupTask? {
        let items = confirmation.allowed
        let work = items.compactMap { item -> CleanupWork? in
            guard let orphan = item.orphan else { return nil }
            return CleanupWork(CleanupItem(name: item.name, resources: [item.folder], estimatedBytes: item.bytes)) {
                let result = await DerivedDataCleaner(environment: self.app.environment).delete([orphan])
                if result.deleted.contains(orphan) {
                    return CleanupItemResult(.cleaned, freedBytes: result.freedBytes, warnings: result.warnings)
                }
                if let refusal = result.refused.first {
                    return CleanupItemResult(.refused, detail: refusal.reason, warnings: result.warnings)
                }
                return CleanupItemResult(.failed, detail: result.failed.first?.message ?? "Nothing was reached.", warnings: result.warnings)
            }
        }
        let task = app.cleanupQueue.enqueue(title: "Xcode DerivedData", unit: "folders", work: work) { _ in
            await self.app.cleanupFinished(rescanWorktrees: false)
            await self.refresh()
        }
        if task != nil { selection.subtract(items.map(\.id)); dismissDelete() }
        return task
    }
}
