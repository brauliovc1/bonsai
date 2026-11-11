import CleanCore
import Foundation

extension WorktreesModel {
    @discardableResult
    public func queueRemoval(_ confirmation: RemovalConfirmation) -> CleanupTask? {
        let items = confirmation.allowed
        let work = items.map { item in
            CleanupWork(CleanupItem(name: item.branchText, resources: [item.worktree.path], estimatedBytes: item.estimatedBytes)) {
                let report = await self.remove([item])
                return report.outcomes.first.map(CleanupItemResult.init) ?? CleanupItemResult(.failed, detail: "Nothing was reached.")
            }
        }
        let task = app.cleanupQueue.enqueue(title: items.count == 1 ? items[0].branchText : "Worktrees", unit: "worktrees", work: work) { task in
            let removed = zip(items, task.items).filter { $0.1.result?.state == .cleaned }.map { $0.0.worktree }
            await self.app.cleanupFinished(removed: removed)
        }
        if task != nil { selection.subtract(items.map(\.id)); dismissRemoval() }
        return task
    }

    @discardableResult
    public func queueRemoveAnyway(_ confirmation: RemoveAnywayConfirmation, understood: Bool) -> CleanupTask? {
        guard understood else { return nil }
        let item = CleanupItem(name: DisplayText.branch(of: confirmation.worktree), resources: [confirmation.worktree.path],
                               estimatedBytes: confirmation.assessment.estimatedBytes)
        let task = app.cleanupQueue.enqueue(title: item.name, unit: "worktrees", work: [CleanupWork(item) {
            let outcome = await self.removeAnyway(confirmation)
            switch outcome {
            case .removed(let result):
                return CleanupItemResult(.cleaned, freedBytes: result.freedBytes,
                                         detail: outcome.text + "\n" + confirmation.lossList.logNotes.joined(separator: "\n"), warnings: result.warnings)
            case .changed(let changes): return CleanupItemResult(.refused, detail: outcome.text + "\n" + changes.joined(separator: "\n"))
            case .failed: return CleanupItemResult(.failed, detail: outcome.text)
            }
        }]) { task in
            let removed = task.cleanedCount == 1 ? [confirmation.worktree] : []
            await self.app.cleanupFinished(removed: removed)
        }
        if task != nil { selection.remove(confirmation.rowID); dismissRemoveAnyway() }
        return task
    }

    @discardableResult
    public func queueLightClean(_ confirmation: LightCleanConfirmation) -> CleanupTask? {
        let task = app.queueFolders(confirmation.cleanable)
        if task != nil { selection.subtract(confirmation.cleanable.map(\.id)); dismissLightClean() }
        return task
    }

    @discardableResult
    public func queuePrune(_ plan: PrunePlan) -> CleanupTask? {
        guard let git = app.git else { return nil }
        let work = plan.prunable.map { repo in
            let resources = ["prune:" + repo.repoPath] + repo.entries.compactMap(\.path)
            return CleanupWork(CleanupItem(name: repo.repoName, resources: resources)) {
                let outcome = await Self.prune(repo, with: Pruner(git: git, environment: self.app.environment))
                let refused = outcome.error != nil || !outcome.refusals.isEmpty
                return CleanupItemResult(outcome.error != nil ? .failed : (refused ? .refused : .cleaned), detail: outcome.summary, warnings: outcome.warnings)
            }
        }
        let task = app.cleanupQueue.enqueue(title: "Missing folders", unit: "repos", work: work) { _ in
            await self.app.cleanupFinished()
        }
        if task != nil { dismissPrune() }
        return task
    }
}
