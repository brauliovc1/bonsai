import CleanCore
import Foundation

extension ProjectsModel {
    /// The projects the one "can free" total counts (PLAN §8.6): ready to clean (idle at least the threshold,
    /// idle known, nothing running inside), leaving out a checkout that is a worktree a removal by hand accepts,
    /// or lies inside one: Worktrees counts that worktree whole, these folders included.
    public var reclaimableRows: [ProjectRow] {
        // Both come from the same scan's records (standardized paths), so plain paths compare.
        let removable = app.removableAssessments.map(\.worktree.path)
        let exact = Set(removable)
        let folders = removable.map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        return allRows.filter { row in
            row.isReady && !exact.contains(row.path) && !folders.contains { row.path.hasPrefix($0) }
        }
    }

    public var reclaimableTotal: ProjectFoldersReport.Total {
        ProjectFoldersReport.total(reclaimableRows.map(\.project))
    }

    /// Shows what the Overview's Project folders card counted.
    public func showReclaimable() {
        filter = .canFree
    }
}
