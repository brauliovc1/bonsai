import CleanCore
import Foundation

extension CachesModel {
    /// The sheet for the rows in `ids`, from a scan made now, because the last one can be old: an entry whose
    /// tool started meanwhile is listed as left alone, and the findings passed to the cleaner are the fresh
    /// scan's own. The screen shows the fresh scan too.
    public func prepareClean(_ ids: Set<CacheRow.ID>) async -> CachesConfirmation {
        let chosen = allRows.filter { ids.contains($0.id) && app.cleanupQueue.task(for: queueResource($0.id)) == nil }
        let fresh = await scanner.scan()
        show(fresh)
        let home = app.environment.homeDirectory
        let items = chosen.map { row -> CachesConfirmation.Item in
            guard let now = fresh.finding(id: row.id) else {
                return CachesConfirmation.Item(row: row, id: row.id, name: row.name, leftAlone: "It no longer exists.")
            }
            let current = CacheRow(finding: now, home: home)
            guard now.isReady else {
                return CachesConfirmation.Item(row: current, id: row.id, name: row.name, leftAlone: current.statusText + ".")
            }
            return CachesConfirmation.Item(row: current, id: row.id, name: row.name, leftAlone: nil)
        }
        return CachesConfirmation(items: items)
    }

    /// Opens the sheet for the ready rows among `ids` (default: the selection) and fills it once the scan is done.
    public func beginClean(_ ids: Set<CacheRow.ID>? = nil) async {
        let ids = (ids ?? selection).intersection(readyRows.map(\.id))
        sheetToken += 1
        let token = sheetToken
        cleanReport = nil
        confirmation = nil
        isShowingCleanSheet = true
        isPreparingClean = true
        let prepared = await prepareClean(ids)
        // Closed (or opened again) while scanning: drop this result.
        guard token == sheetToken, isShowingCleanSheet else { return }
        confirmation = prepared
        isPreparingClean = false
    }

    /// Closes the sheet; not while cleaning.
    public func dismissClean() {
        guard !isCleaning else { return }
        sheetToken += 1
        isShowingCleanSheet = false
        isPreparingClean = false
        confirmation = nil
        cleanReport = nil
    }

    /// Cleans what the open sheet lists, or, with no sheet open, the selection after a fresh scan.
    @discardableResult
    public func cleanSelected() async -> CachesCleanReport {
        let listed: CachesConfirmation
        if let confirmation {
            listed = confirmation
        } else {
            listed = await prepareClean(selection)
        }
        return await confirmClean(listed)
    }

    /// Cleans the confirmation's ready entries through `ToolCacheCleaner`, inside the app's cleanup guard and
    /// `cleanup.lock`; refused, deleting nothing, while another cleanup holds either. The cleaner checks each
    /// entry again right before it. Then the screen scans again.
    @discardableResult
    public func confirmClean(_ confirmation: CachesConfirmation) async -> CachesCleanReport {
        let items = confirmation.allowed
        guard !items.isEmpty, !isCleaning else { return .empty }
        isCleaning = true
        let cleaner = ToolCacheCleaner(environment: app.environment, processes: processes)
        let app = app
        let result = await app.cleaningUp {
            await cleaner.clean(items.compactMap(\.finding)) { await !app.isQuitting }
        }
        let report = CachesCleanReport(items: items, result: result, busy: app.busyReason)
        cleanReport = report
        selection.subtract(report.outcomes.filter(\.isCleaned).map(\.id))
        isCleaning = false
        if result != nil {
            await app.cleanupFinished(rescanWorktrees: false)
            await refresh()
        }
        return report
    }
}
