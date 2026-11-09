import CleanCore
import Foundation

/// One line of the Worktrees table: a repo's group header or a worktree. The table shows both through
/// the same columns, so this carries a sort key for each; the model sorts, the table only names the column.
public enum WorktreeTableItem: Identifiable, Hashable, Sendable {
    case group(WorktreeGroup)
    case worktree(WorktreeRow)

    public enum ID: Hashable, Sendable {
        case group(String)
        case worktree(WorktreeRow.ID)
    }

    public var id: ID {
        switch self {
        case .group(let group): .group(group.repoPath)
        case .worktree(let row): .worktree(row.id)
        }
    }

    public var row: WorktreeRow? {
        if case .worktree(let row) = self { return row }
        return nil
    }

    // MARK: - Sort keys (a group's are only there to fill the column)

    /// The first column: the repo name on a group, the branch on a worktree.
    public var nameSortKey: String {
        switch self {
        case .group(let group): group.name
        case .worktree(let row): row.branchText
        }
    }
    public var kindText: String { row?.kindText ?? "" }
    public var lastCommitSortKey: Date { row?.lastCommitSortKey ?? .distantPast }
    public var folderText: String {
        switch self {
        case .group(let group): group.folderText
        case .worktree(let row): row.folderText
        }
    }
    public var sizeSortKey: Int64 { row?.sizeSortKey ?? -1 }
    public var dependencySortKey: Int64 { row?.dependencySortKey ?? -1 }
    public var idleSortKey: Int { row?.idleSortKey ?? -1 }
    public var statusSortKey: Int { row?.statusSortKey ?? -1 }

    // MARK: - The table's sort order <-> the model's

    /// The model's sort order as the table's columns name it. Keys no column shows are left out.
    public static func tableSortOrder(_ order: [KeyPathComparator<WorktreeRow>]) -> [KeyPathComparator<WorktreeTableItem>] {
        order.compactMap { comparator in
            sortKeys().first { $0.rows.contains(comparator.keyPath) }?.item(comparator.order)
        }
    }

    /// The table's sort order (a column header was clicked) as the model sorts rows.
    public static func rowSortOrder(_ order: [KeyPathComparator<WorktreeTableItem>]) -> [KeyPathComparator<WorktreeRow>] {
        order.compactMap { comparator in
            sortKeys().first { $0.itemKey == comparator.keyPath }?.row(comparator.order)
        }
    }

    /// One column's key on both sides. `rows`: the row keys shown by it, the first is the one a click sets.
    private struct SortKey {
        var itemKey: PartialKeyPath<WorktreeTableItem>
        var rows: [PartialKeyPath<WorktreeRow>]
        var item: (SortOrder) -> KeyPathComparator<WorktreeTableItem>
        var row: (SortOrder) -> KeyPathComparator<WorktreeRow>
    }

    private static func key<I: Comparable, R: Comparable>(
        _ item: KeyPath<WorktreeTableItem, I> & Sendable,
        _ row: KeyPath<WorktreeRow, R> & Sendable,
        alsoShowing others: [PartialKeyPath<WorktreeRow>] = []
    ) -> SortKey {
        SortKey(
            itemKey: item,
            rows: [row] + others,
            item: { KeyPathComparator(item, order: $0) },
            row: { KeyPathComparator(row, order: $0) }
        )
    }

    private static func sortKeys() -> [SortKey] {
        [
            // The default sort (repo name) shows on the first column too: groups are in repo order.
            key(\.nameSortKey, \.branchText, alsoShowing: [\WorktreeRow.repoName]),
            key(\.kindText, \.kindText),
            key(\.lastCommitSortKey, \.lastCommitSortKey),
            key(\.folderText, \.folderText),
            key(\.sizeSortKey, \.sizeSortKey),
            key(\.dependencySortKey, \.dependencySortKey),
            key(\.idleSortKey, \.idleSortKey),
            key(\.statusSortKey, \.statusSortKey),
        ]
    }
}
