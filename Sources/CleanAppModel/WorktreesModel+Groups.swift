import CleanCore
import Foundation

extension WorktreesModel {
    /// The shown worktrees grouped by repo, each under its main checkout. A repo shows when the filter and search
    /// leave at least one of its linked worktrees. Rows and groups follow "Sort by" (`WorktreesModel+Sort`).
    public var groups: [WorktreeGroup] {
        var order: [String] = []
        var mains: [String: WorktreeRow] = [:]
        var totals: [String: Int] = [:]
        var sizes: [String: Int64] = [:]
        var unknownSizes = Set<String>()
        var byRepo: [String: [WorktreeRow]] = [:]
        for row in allRows {
            let repo = row.worktree.repoPath
            if row.worktree.isMain {
                mains[repo] = row
                continue
            }
            totals[repo, default: 0] += 1
            if let bytes = row.sizeBytes { sizes[repo, default: 0] += bytes }
            else { unknownSizes.insert(repo) }
            guard matches(row) else { continue }
            if byRepo[repo] == nil { order.append(repo) }
            byRepo[repo, default: []].append(row)
        }
        let home = app.environment.homeDirectory
        let groups = order.map { repo in
            WorktreeGroup(
                repoPath: repo,
                main: mains[repo],
                rows: (byRepo[repo] ?? []).sorted { rowPrecedes($0, $1, flat: false) },
                totalCount: totals[repo] ?? 0,
                worktreeBytes: sizes[repo],
                hasUnknownWorktreeSizes: unknownSizes.contains(repo),
                remotes: app.scan?.remotes?[repo] ?? [],
                home: home
            )
        }
        return groups.sorted(by: groupPrecedes)
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
