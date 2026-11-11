import CleanCore
import Foundation

extension WorktreesModel {
    /// The label loads the same catalog as Compare, so remote defaults and master repos stay accurate.
    public func compareBase(for repo: String) async -> String {
        guard let executable = app.git?.executable,
              let git = try? GitReadOnly(repository: URL(fileURLWithPath: repo), executable: executable),
              let catalog = try? await RefCatalog.load(using: git) else { return "base branch" }
        return catalog.defaultBase ?? "HEAD"
    }

    public func openCompare(_ row: WorktreeRow) { onCompare?(row.worktree.repoPath, .worktree(row.path)) }
    public var compareSelection: WorktreeRow? {
        let all = selectedRows + selectedRepos
        return all.count == 1 && all[0].isOpenableFolder ? all[0] : nil
    }
}
