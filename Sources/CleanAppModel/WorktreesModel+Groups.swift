import CleanCore
import Foundation

extension WorktreesModel {
    /// The shown rows grouped by repo. Groups are in name order (reversed when the sort's first key is the
    /// repo or branch name, descending); inside a group the sort applies, ties keep scan order, and the main
    /// checkout stays first. Header counts and sizes are those of the shown rows.
    public var groups: [WorktreeGroup] {
        let all = allRows
        let totals = Dictionary(grouping: all, by: \.worktree.repoPath).mapValues(\.count)
        let comparators = sortOrder + [KeyPathComparator(\WorktreeRow.scanOrder)]
        var order: [String] = []
        var byRepo: [String: [WorktreeRow]] = [:]
        for row in all where matches(row) {
            let repo = row.worktree.repoPath
            if byRepo[repo] == nil { order.append(repo) }
            byRepo[repo, default: []].append(row)
        }
        let home = app.environment.homeDirectory
        let groups = order.map { repo in
            let sorted = (byRepo[repo] ?? []).sorted(using: comparators)
            let rows = sorted.filter(\.worktree.isMain) + sorted.filter { !$0.worktree.isMain }
            return WorktreeGroup(
                repoPath: repo,
                rows: rows,
                totalCount: totals[repo] ?? rows.count,
                remotes: app.scan?.remotes?[repo] ?? [],
                home: home
            )
        }
        let descending = groupNameOrder == .reverse
        return groups.sorted { lhs, rhs in
            let names = lhs.name.localizedStandardCompare(rhs.name)
            if names != .orderedSame { return descending ? names == .orderedDescending : names == .orderedAscending }
            return descending ? lhs.repoPath > rhs.repoPath : lhs.repoPath < rhs.repoPath
        }
    }

    /// The direction of the repo order: the sort's when it starts with the repo or branch name.
    var groupNameOrder: SortOrder {
        guard let first = sortOrder.first else { return .forward }
        let byName: [PartialKeyPath<WorktreeRow>] = [\WorktreeRow.repoName, \WorktreeRow.branchText]
        return byName.contains(first.keyPath) ? first.order : .forward
    }

    public func isExpanded(_ repoPath: String) -> Bool {
        !collapsedRepos.contains(repoPath)
    }

    /// Collapsing a group also deselects its rows, so nothing hidden is removed or cleaned.
    public func setExpanded(_ expanded: Bool, repo repoPath: String) {
        if expanded {
            collapsedRepos.remove(repoPath)
        } else {
            collapsedRepos.insert(repoPath)
            selection = selection.filter { $0.repoPath != repoPath }
        }
    }

    /// What the details panel shows: one selected row, several (a summary), or none.
    public var detailsSelection: DetailsSelection {
        let selected = selectedRows
        switch selected.count {
        case 0: return .none
        case 1: return .one(selected[0])
        default: return .several(WorktreeSelectionSummary(rows: selected))
        }
    }

    public enum DetailsSelection: Equatable, Sendable {
        case none
        case one(WorktreeRow)
        case several(WorktreeSelectionSummary)
    }
}
