import CleanCore

extension RemovalsModel {
    public func putBackUnavailableReason(_ row: RemovalLogRow) -> String? {
        DownloadPutBack(home: app.environment.homeDirectory, log: RemovalLog(environment: app.environment))
            .unavailableReason(row.entry)
    }

    @discardableResult
    public func queuePutBack(_ id: RemovalLogRow.ID) -> CleanupTask? {
        guard let row = rows.first(where: { $0.id == id }), row.entry.action == .movedToTrash,
              putBackUnavailableReason(row) == nil else { return nil }
        let putBack = DownloadPutBack(home: app.environment.homeDirectory, log: RemovalLog(environment: app.environment), now: app.environment.now)
        let item = CleanupItem(name: row.path, resources: [row.path, row.entry.trashPath ?? "trash"])
        return app.cleanupQueue.enqueue(title: "Put back download", unit: "files", work: [CleanupWork(item) {
            do {
                _ = try putBack.putBack(row.entry)
                return CleanupItemResult(.cleaned, detail: "Put back in Downloads")
            } catch { return CleanupItemResult(.failed, detail: error.localizedDescription) }
        }]) { _ in await self.app.cleanupFinished(rescanWorktrees: false) }
    }
}
