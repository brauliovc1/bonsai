import CleanCore
import Foundation

/// One line of the Project folders table: a repo's header or a project. Both go through the same columns, so
/// each carries the sort keys; the model sorts groups by their keys and rows inside a group by theirs.
public enum ProjectTableItem: Identifiable, Hashable, Sendable {
    case group(ProjectGroup)
    case project(ProjectRow)

    public enum ID: Hashable, Sendable {
        case group(String)
        case project(ProjectRow.ID)
    }

    public var id: ID {
        switch self {
        case .group(let group): .group(group.repoPath)
        case .project(let row): .project(row.id)
        }
    }

    public var row: ProjectRow? {
        if case .project(let row) = self { return row }
        return nil
    }

    public var nameSortKey: String {
        switch self {
        case .group(let group): group.name.lowercased()
        case .project(let row): row.nameSortKey
        }
    }

    /// A group sorts by its most recently used project.
    public var idleSortKey: Int {
        switch self {
        case .group(let group): group.rows.map(\.idleSortKey).min() ?? -1
        case .project(let row): row.idleSortKey
        }
    }

    public var foldersText: String { row?.foldersText ?? "" }

    /// The last tie-breaker: the repo folder or the project's.
    public var pathSortKey: String {
        switch self {
        case .group(let group): group.repoPath
        case .project(let row): row.path
        }
    }

    public var sizeSortKey: Int64 {
        switch self {
        case .group(let group): group.totalBytes
        case .project(let row): row.sizeBytes
        }
    }

    public var statusSortKey: Int {
        switch self {
        case .group(let group): group.rows.map(\.statusSortKey).min() ?? -1
        case .project(let row): row.statusSortKey
        }
    }
}
