import CleanCore
import Foundation

extension AppModel {
    /// Each folder gets its own turn through the unchanged light-clean path, including its linked-use and
    /// identity checks. Singleton calls let Stop finish the current folder without entering the next one.
    func queueFolders(_ items: [LightCleanConfirmation.Item],
                      beforeFinish: @escaping @MainActor () -> Void = {},
                      afterFinish: @escaping @MainActor () async -> Void = {}) -> CleanupTask? {
        let work = items.flatMap { item in
            item.candidates.map { candidate in
                CleanupWork(CleanupItem(name: item.worktree.url.lastPathComponent + "/" + candidate.relativePath,
                                       resources: [candidate.path], estimatedBytes: candidate.estimatedBytes)) {
                    let one = LightCleanConfirmation.Item(worktree: item.worktree,
                        findings: LightCleanFindings(worktree: item.worktree, candidates: [candidate]), blocker: item.blocker)
                    let outcomes = await LightCleanFlow(app: self).clean([one])
                    return outcomes.first.map(CleanupItemResult.init) ?? CleanupItemResult(.failed, detail: "Nothing was reached.")
                }
            }
        }
        let title = items.count == 1 ? items[0].worktree.url.lastPathComponent : "Project folders"
        return cleanupQueue.enqueue(title: title, unit: "folders", work: work) { _ in
            beforeFinish()
            await self.cleanupFinished(rescanWorktrees: false, touched: items.map(\.worktree))
            await afterFinish()
        }
    }
}
