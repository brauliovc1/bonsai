import CleanCore
import Foundation

extension WorktreesModel {
    /// The segmented filter (PLAN §8.4). Only linked worktrees are counted: a repo's main checkout is its group's
    /// header, never a row.
    public enum Filter: String, CaseIterable, Sendable, Identifiable {
        /// What a removal by hand would accept (the Overview's Worktrees card counts the same ones).
        case canRemove
        /// The orange chips: local work, unreachable commits, other repos inside, ignored files.
        case needsAttention
        case all

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .canRemove: "Can remove"
            case .needsAttention: "Needs attention"
            case .all: "All"
            }
        }

        public func includes(_ row: WorktreeRow) -> Bool {
            guard !row.worktree.isMain else { return false }
            switch self {
            case .canRemove: return row.canRemove
            case .needsAttention: return row.needsAttention
            case .all: return true
            }
        }
    }

    /// How many linked worktrees the filter shows, with the search applied.
    public func count(_ filter: Filter) -> Int {
        linkedRows.count { filter.includes($0) && matchesSearch($0) }
    }

    /// "Can remove · 7".
    public func title(_ filter: Filter) -> String {
        "\(filter.title) · \(count(filter))"
    }

    func matches(_ row: WorktreeRow) -> Bool {
        filter.includes(row) && matchesSearch(row)
    }

    func matchesSearch(_ row: WorktreeRow) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return row.searchableTexts.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    /// Shows what the Overview's Worktrees card counted: "Can remove", no search.
    public func showRemovable() {
        filter = .canRemove
        searchText = ""
    }
}
