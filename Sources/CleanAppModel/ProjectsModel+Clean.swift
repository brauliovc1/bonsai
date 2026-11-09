import CleanCore
import Foundation

extension ProjectsModel {
    /// The sheet for the shown rows in `ids` (a row the filter hides is left out), from a fresh look at each
    /// project: the light-clean sheet's look (git's current record, the repo's own folder, a process index
    /// taken now, `LightCleanFinder` run again), the idle clock read again, and the rebuild lines for what was
    /// found. Listed folders are the ones `cleanSelected` deletes; the rest is shown with its reasons and left
    /// alone. A row "Select all idle" picked (`autoPicked`) whose idle days read now fall below the threshold, or
    /// became unknown, is listed as changed and not deleted unless the user ticks it (`setIncluded`).
    public func prepareClean(_ ids: Set<ProjectRow.ID>) async -> ProjectsConfirmation {
        let chosen = rows.filter { ids.contains($0.id) }
        let autoPicked = Set(chosen.map(\.path).filter { self.autoPicked.contains($0) })
        guard !chosen.isEmpty else { return ProjectsConfirmation(items: []) }
        let looked = await LightCleanFlow(app: app).look(at: chosen.map(\.worktree))
        let threshold = self.threshold
        let known = app.scan?.worktrees ?? []
        guard let git = app.git else {
            return ProjectsConfirmation(items: looked.map {
                ProjectsConfirmation.Item(
                    lightClean: $0, idle: .unknown, threshold: threshold, rebuildLines: [],
                    wasAutoPicked: autoPicked.contains($0.worktree.path)
                )
            })
        }
        let scanner = scanner(git: git)
        let items = await BoundedConcurrency.map(looked, limit: LightCleanFlow.lookConcurrency) { item in
            let idle = await scanner.idleReport(for: item.worktree, known: known)
            let lines = ProjectFoldersScanner.rebuildLines(in: item.worktree.url, candidates: item.candidates.map(\.relativePath))
            return ProjectsConfirmation.Item(
                lightClean: item, idle: idle, threshold: threshold, rebuildLines: lines,
                wasAutoPicked: autoPicked.contains(item.worktree.path)
            )
        }
        return ProjectsConfirmation(items: items)
    }

    /// Opens the sheet for `ids` (default: the selection) and fills it once the look is done.
    public func beginClean(_ ids: Set<ProjectRow.ID>? = nil) async {
        let ids = ids ?? selection
        cleanSheetToken += 1
        let token = cleanSheetToken
        cleanReport = nil
        confirmation = nil
        isShowingCleanSheet = true
        isPreparingClean = true
        let prepared = await prepareClean(ids)
        // Closed (or opened again) while looking: drop this result.
        guard token == cleanSheetToken, isShowingCleanSheet else { return }
        confirmation = prepared
        isPreparingClean = false
    }

    /// Ticks (or unticks) a changed project in the sheet, so its folders are deleted too.
    public func setIncluded(_ id: ProjectsConfirmation.Item.ID, _ included: Bool) {
        guard !isCleaning, var confirmation, confirmation.changed.contains(where: { $0.id == id }) else { return }
        if included { confirmation.included.insert(id) } else { confirmation.included.remove(id) }
        self.confirmation = confirmation
    }

    /// Closes the sheet; not while folders are being deleted.
    public func dismissClean() {
        guard !isCleaning else { return }
        cleanSheetToken += 1
        isShowingCleanSheet = false
        isPreparingClean = false
        confirmation = nil
        cleanReport = nil
    }

    /// Deletes the listed folders, one project after another, through the light-clean path Worktrees uses
    /// (`LightCleanFlow.clean`: `LightCleaner` with a `LightCleanExpectation` of the record the sheet showed,
    /// every folder checked again right before its delete, one log entry per folder), holding the app's cleanup
    /// guard and `cleanup.lock`; refused as a whole while another cleanup holds either. A project that is
    /// refused doesn't stop the next. Then the log, free space and worktrees are read again and the cleaned
    /// projects are looked at again.
    @discardableResult
    public func cleanSelected(_ confirmation: ProjectsConfirmation) async -> LightCleanReport {
        let items = confirmation.cleanable.map(\.lightClean)
        guard !items.isEmpty, !isCleaning else { return LightCleanReport(outcomes: []) }
        isCleaning = true
        cleansDone = 0
        let finished = await app.cleaningUp {
            await LightCleanFlow(app: app).clean(items) { cleansDone += 1 }
        }
        let busy = app.busyReason
        let outcomes = finished ?? items.map {
            LightCleanOutcome(item: $0, error: "\(busy); nothing was deleted")
        }
        let report = LightCleanReport(outcomes: outcomes)
        cleanReport = report
        isCleaning = false
        if finished != nil {
            // The log entries this clean wrote name these projects; they are looked at once, here.
            isFinishingClean = true
            await app.cleanupFinished()
            isFinishingClean = false
            let paths = Set(items.map(\.worktree.path)).union(namedByLog)
            namedByLog = []
            await rescan(paths)
        }
        return report
    }
}
