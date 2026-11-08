import CleanCore
import Foundation

extension DerivedDataModel {
    /// The sheet for the selected rows in `ids`, from a scan made now, because the last one can be old: an
    /// orphan whose project came back is listed as left alone, and the orphans passed to the cleaner are
    /// the fresh scan's own. A refused root lists everything as left alone.
    public func prepareDelete(_ ids: Set<DerivedDataRow.ID>) async -> DerivedDataConfirmation {
        let chosen = rows.filter { ids.contains($0.id) }
        let fresh = await DerivedDataScanner.scan(environment: app.environment, runner: runner)
        let items = chosen.map { row -> DerivedDataConfirmation.Item in
            if let refusal = fresh.refusal {
                return Self.item(row, now: nil, leftAlone: "The DerivedData folder is refused: \(refusal)")
            }
            guard let now = fresh.entries.first(where: { $0.folder == row.id }) else {
                return Self.item(row, now: nil, leftAlone: "It no longer exists.")
            }
            guard now.orphan != nil else {
                let why = DerivedDataRow(entry: now).reason
                return Self.item(row, now: now, leftAlone: "It isn't orphaned: \(why)")
            }
            return Self.item(row, now: now, leftAlone: nil)
        }
        return DerivedDataConfirmation(root: fresh.root, refusal: fresh.refusal, items: items)
    }

    /// Opens the sheet for the orphaned rows among `ids` (default: the selection; read-only rows don't count)
    /// and fills it once the scan is done.
    public func beginDelete(_ ids: Set<DerivedDataRow.ID>? = nil) async {
        let ids = (ids ?? selection).intersection(selectableIDs)
        deleteSheetToken += 1
        let token = deleteSheetToken
        cleanupReport = nil
        confirmation = nil
        isShowingDeleteSheet = true
        isPreparingDelete = true
        let prepared = await prepareDelete(ids)
        // Closed (or opened again) while scanning: drop this result.
        guard token == deleteSheetToken, isShowingDeleteSheet else { return }
        confirmation = prepared
        isPreparingDelete = false
    }

    /// Closes the sheet; not while folders are being deleted.
    public func dismissDelete() {
        guard !isDeleting else { return }
        deleteSheetToken += 1
        isShowingDeleteSheet = false
        isPreparingDelete = false
        confirmation = nil
        cleanupReport = nil
    }

    /// Deletes the listed orphans through `DerivedDataCleaner`, which checks each one again right before it
    /// deletes it (the project must still be missing, the root still acceptable). Only the confirmation's
    /// orphans are passed. Then the screen scans again.
    @discardableResult
    public func confirmDelete(_ confirmation: DerivedDataConfirmation) async -> DerivedDataCleanupReport {
        let items = confirmation.allowed
        guard !items.isEmpty, !isDeleting else { return DerivedDataCleanupReport(outcomes: [], measuredFreedBytes: nil, warnings: []) }
        isDeleting = true
        deletesDone = 0
        let cleaner = DerivedDataCleaner(environment: app.environment)
        let deletion = await app.cleaningUp { await cleaner.delete(items.compactMap(\.orphan)) }
        let report = Self.report(for: items, deletion: deletion, busy: app.busyReason)
        cleanupReport = report
        selection.subtract(report.outcomes.filter(\.isDeleted).map(\.id))
        isDeleting = false
        if deletion != nil {
            await app.cleanupFinished(rescanWorktrees: false)
            await refresh()
        }
        return report
    }

    /// `busy`: why nothing ran when `deletion` is nil (another cleanup holds the guard).
    private static func report(
        for items: [DerivedDataConfirmation.Item],
        deletion: DerivedDataDeletion?,
        busy: String
    ) -> DerivedDataCleanupReport {
        guard let deletion else {
            let outcomes = items.map {
                DerivedDataOutcome(item: $0, status: .refused("\(busy); nothing was deleted"))
            }
            return DerivedDataCleanupReport(outcomes: outcomes, measuredFreedBytes: nil, warnings: [])
        }
        let outcomes = items.map { item -> DerivedDataOutcome in
            let status: DerivedDataOutcome.Status
            if deletion.deleted.contains(where: { $0.folder == item.folder }) {
                status = .deleted(freedBytes: deletion.entries.first { $0.path == item.folder }?.freedBytes)
            } else if let failure = deletion.failed.first(where: { $0.orphan.folder == item.folder }) {
                status = .failed(failure.message)
            } else if let refusal = deletion.refused.first(where: { $0.orphan.folder == item.folder }) {
                status = .refused(refusal.reason)
            } else {
                status = .refused("it was not reached")
            }
            return DerivedDataOutcome(item: item, status: status)
        }
        return DerivedDataCleanupReport(outcomes: outcomes, measuredFreedBytes: deletion.freedBytes, warnings: deletion.warnings)
    }

    private static func item(_ row: DerivedDataRow, now: DerivedDataEntry?, leftAlone: String?) -> DerivedDataConfirmation.Item {
        DerivedDataConfirmation.Item(
            folder: row.id,
            name: row.name,
            state: now?.state,
            workspacePath: now?.workspacePath ?? row.entry.workspacePath,
            bytes: now?.bytes ?? row.bytes,
            orphan: leftAlone == nil ? now?.orphan : nil,
            leftAloneReason: leftAlone
        )
    }
}
