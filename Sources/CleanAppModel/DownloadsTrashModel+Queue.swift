import CleanCore
import Foundation

extension DownloadsTrashModel {
    @discardableResult
    public func queueMove(_ confirmation: DownloadsConfirmation) -> CleanupTask? {
        guard moveConfirmation?.id == confirmation.id else { return nil }
        let mover = DownloadsMover(scanner: scanner, log: RemovalLog(environment: app.environment), trash: trashOperation)
        let work = confirmation.files.map { file in
            CleanupWork(CleanupItem(name: file.name, resources: [file.path], estimatedBytes: file.bytes)) {
                let result = await mover.move(file)
                let status: CleanupItemResult.State = switch result.status {
                case .moved: .cleaned
                case .refused: .refused
                case .failed: .failed
                }
                return CleanupItemResult(status, freedBytes: nil, detail: result.reason, warnings: result.warnings)
            }
        }
        let task = app.cleanupQueue.enqueue(title: "Move downloads to Trash", unit: "files", work: work) { _ in
            await self.app.cleanupFinished(rescanWorktrees: false)
            await self.refresh()
        }
        if task != nil { selection.subtract(confirmation.files.map(\.id)); moveConfirmation = nil }
        return task
    }

    @discardableResult
    public func confirmEmptyTrash() -> CleanupTask? {
        guard isShowingEmptySheet, canEmptyTrash, let confirmedTrash else { return nil }
        guard !confirmedTrash.info.readable || confirmedTrash.fingerprint != .unreadable else { return nil }
        let flow = EmptyTrashFlow(emptier: emptier, log: RemovalLog(environment: app.environment),
                                  home: app.environment.homeDirectory, now: app.environment.now)
        let item = CleanupItem(name: "Trash", resources: ["trash", app.environment.homeDirectory.appending(path: ".Trash").path])
        let task = app.cleanupQueue.enqueue(title: "Empty Trash", unit: "actions", work: [CleanupWork(item) {
            do {
                let result = try await flow.run(confirmed: true, expected: confirmedTrash.fingerprint)
                self.automationDenied = false
                return CleanupItemResult(.cleaned, freedBytes: result?.entry.freedBytes,
                                         detail: "Finder emptied the Trash", warnings: result?.warnings ?? [])
            } catch {
                if case TrashEmptyError.contentsChanged = error {
                    return CleanupItemResult(.refused, detail: error.localizedDescription)
                }
                if case TrashEmptyError.automationDenied = error { self.automationDenied = true }
                return CleanupItemResult(.failed, detail: error.localizedDescription)
            }
        }]) { _ in
            await self.app.cleanupFinished(rescanWorktrees: false)
            await self.refresh()
        }
        if task != nil { isShowingEmptySheet = false; self.confirmedTrash = nil }
        return task
    }
}
