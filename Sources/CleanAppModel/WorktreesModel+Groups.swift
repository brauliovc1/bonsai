import CleanCore
import Foundation

extension WorktreesModel {
    /// The shown worktrees grouped by repo, each under its main checkout. A repo shows when the filter and search
    /// leave at least one of its linked worktrees. Groups are in name order (reversed when the sort's first key is
    /// the repo or branch name, descending); inside a group the sort applies and ties keep scan order.
    public var groups: [WorktreeGroup] {
        let all = allRows
        let comparators = sortOrder + [KeyPathComparator(\WorktreeRow.scanOrder)]
        var order: [String] = []
        var mains: [String: WorktreeRow] = [:]
        var totals: [String: Int] = [:]
        var sizes: [String: Int64] = [:]
        var byRepo: [String: [WorktreeRow]] = [:]
        for row in all {
            let repo = row.worktree.repoPath
            if row.worktree.isMain {
                mains[repo] = row
                continue
            }
            totals[repo, default: 0] += 1
            if let bytes = row.sizeBytes { sizes[repo, default: 0] += bytes }
            guard matches(row) else { continue }
            if byRepo[repo] == nil { order.append(repo) }
            byRepo[repo, default: []].append(row)
        }
        let home = app.environment.homeDirectory
        let groups = order.map { repo in
            WorktreeGroup(
                repoPath: repo,
                main: mains[repo],
                rows: (byRepo[repo] ?? []).sorted(using: comparators),
                totalCount: totals[repo] ?? 0,
                worktreeBytes: sizes[repo],
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

    public func toggleExpanded(_ repoPath: String) {
        setExpanded(!isExpanded(repoPath), repo: repoPath)
    }

    /// Collapsing a group also deselects its rows, so nothing hidden is removed or cleaned. The state is kept
    /// while the app runs (across screens and scans).
    public func setExpanded(_ expanded: Bool, repo repoPath: String) {
        if expanded {
            collapsedRepos.remove(repoPath)
        } else {
            collapsedRepos.insert(repoPath)
            // The header stays selectable; its worktrees are hidden.
            let header = Set(allRows.filter { $0.worktree.isMain && $0.worktree.repoPath == repoPath }.map(\.id))
            selection = selection.filter { $0.repoPath != repoPath || header.contains($0) }
        }
    }

    /// What the details panel shows: one selected worktree or repo folder, several (a summary), or none.
    public var detailsSelection: DetailsSelection {
        let selected = selectedRepos + selectedRows
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
