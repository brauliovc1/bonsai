import CleanCore
import Foundation

extension WorktreesModel {
    public func revealWorktree(_ path: String) {
        guard let row = allRows.first(where: { CanonicalPath.same($0.url, URL(fileURLWithPath: path)) }) else { return }
        filter = .all; searchText = ""
        collapsedRepos.remove(row.worktree.repoPath)
        selection = [row.id]
        isShowingDetails = true
    }
}
