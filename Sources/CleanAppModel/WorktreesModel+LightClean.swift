import CleanCore
import Foundation

extension WorktreesModel {
    /// The sheet for the shown worktrees and repo folders in `ids`, from a fresh look at each one
    /// (`LightCleanFlow.look`: git's current record, the repo's own folder, a process index taken now,
    /// `LightCleanFinder` run again). Listed folders are the ones `confirmLightClean` deletes; the rest is
    /// shown with its reasons and left alone.
    public func prepareLightClean(_ ids: Set<WorktreeRow.ID>) async -> LightCleanConfirmation {
        let chosen = (groups.compactMap(\.main) + rows).filter { ids.contains($0.id) }
        return LightCleanConfirmation(items: await LightCleanFlow(app: app).look(at: chosen.map(\.worktree)))
    }

    /// Opens the light-clean sheet for `ids` (default: the selection) and fills it once the look is done.
    public func beginLightClean(_ ids: Set<WorktreeRow.ID>? = nil) async {
        let ids = ids ?? selection
        lightCleanSheetToken += 1
        let token = lightCleanSheetToken
        lightCleanReport = nil
        lightCleanConfirmation = nil
        isShowingLightCleanSheet = true
        isPreparingLightClean = true
        let prepared = await prepareLightClean(ids)
        // Closed (or opened again) while looking: drop this result.
        guard token == lightCleanSheetToken, isShowingLightCleanSheet else { return }
        lightCleanConfirmation = prepared
        isPreparingLightClean = false
    }

    /// Closes the sheet; not while folders are being deleted.
    public func dismissLightClean() {
        guard !isLightCleaning else { return }
        lightCleanSheetToken += 1
        isShowingLightCleanSheet = false
        isPreparingLightClean = false
        lightCleanConfirmation = nil
        lightCleanReport = nil
    }

    /// Deletes the listed folders, one worktree at a time, through `LightCleaner`, which checks each folder
    /// again right before it deletes it, and refuses a worktree that is no longer this repo's or whose branch
    /// or HEAD is not what the sheet showed. A folder that changed since the sheet listed it is refused with
    /// its reason, and nothing the sheet didn't list is touched. Then the cleaned checkouts' sizes and
    /// dependency folders are measured again, just those (no full rescan: the verdicts don't depend on these
    /// folders), and their rows show "Measuring…" until then.
    @discardableResult
    public func confirmLightClean(_ confirmation: LightCleanConfirmation) async -> LightCleanReport {
        let items = confirmation.cleanable
        guard !items.isEmpty, !isLightCleaning else { return LightCleanReport(outcomes: []) }
        isLightCleaning = true
        lightCleansDone = 0
        let finished = await app.cleaningUp { await clean(items) }
        let busy = app.busyReason
        let outcomes = finished ?? items.map {
            LightCleanOutcome(item: $0, error: "\(busy); nothing was deleted")
        }
        let report = LightCleanReport(outcomes: outcomes)
        lightCleanReport = report
        isLightCleaning = false
        if finished != nil {
            await app.cleanupFinished(rescanWorktrees: false, touched: items.map(\.worktree))
        }
        return report
    }

    private func clean(_ items: [LightCleanConfirmation.Item]) async -> [LightCleanOutcome] {
        await LightCleanFlow(app: app).clean(items) { lightCleansDone += 1 }
    }
}
