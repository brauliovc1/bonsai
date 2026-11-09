import Foundation

/// "Sort by" and "Group by repo" (P12b addition, 11-09): one order for rows, repo groups and the flat list. Kept in
/// memory while the app runs (not in UserDefaults, which development runs would share with the installed Bonsai).
extension WorktreesModel {
    public enum SortKey: String, CaseIterable, Sendable, Identifiable {
        /// Largest first; a group by its shown worktrees' total (the repo folder isn't removable, so it doesn't count).
        case size
        /// Oldest last activity first; a group by its oldest shown worktree.
        case activity
        /// By name: groups by repo, rows by branch (in the flat list, repo then branch).
        case name

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .size: "Size"
            case .activity: "Last activity"
            case .name: "Name"
            }
        }
    }

    /// The shown worktrees of every repo in one list, in the sort's order ("Group by repo" off).
    public var flatRows: [WorktreeRow] {
        linkedRows.filter(matches).sorted { rowPrecedes($0, $1, flat: true) }
    }

    /// Whether `lhs` comes before `rhs` in a group (or, `flat`, in the list across repos). Ties keep scan order.
    func rowPrecedes(_ lhs: WorktreeRow, _ rhs: WorktreeRow, flat: Bool) -> Bool {
        let decided: Bool? = switch sortKey {
        case .size:
            Self.precedes(Self.sortSize(lhs), Self.sortSize(rhs), descending: true)
        case .activity:
            Self.precedes(lhs.idleDays, rhs.idleDays, descending: true)
        case .name:
            (flat ? Self.precedes(name: lhs.repoName, rhs.repoName) : nil)
                ?? Self.precedes(name: lhs.branchText, rhs.branchText)
        }
        return decided ?? (lhs.scanOrder < rhs.scanOrder)
    }

    /// Whether group `lhs` comes before `rhs`. Ties (and Name) go by repo name, then folder.
    func groupPrecedes(_ lhs: WorktreeGroup, _ rhs: WorktreeGroup) -> Bool {
        let decided: Bool? = switch sortKey {
        case .size:
            Self.precedes(Self.shownSize(lhs), Self.shownSize(rhs), descending: true)
        case .activity:
            Self.precedes(lhs.rows.compactMap(\.idleDays).max(), rhs.rows.compactMap(\.idleDays).max(), descending: true)
        case .name:
            nil
        }
        return decided ?? Self.precedes(name: lhs.name, rhs.name) ?? (lhs.repoPath < rhs.repoPath)
    }

    /// The size a row sorts by: nil while it is measured again or when unknown, so it goes last, never first.
    static func sortSize(_ row: WorktreeRow) -> Int64? {
        row.isMeasuringSize ? nil : row.sizeBytes
    }

    /// The group's shown worktrees added up (those with a known size); nil when none has one.
    static func shownSize(_ group: WorktreeGroup) -> Int64? {
        let sizes = group.rows.compactMap(sortSize)
        return sizes.isEmpty ? nil : sizes.reduce(0, +)
    }

    /// true or false when the values decide; nil when they tie. An unknown value goes last in either direction.
    static func precedes<T: Comparable>(_ lhs: T?, _ rhs: T?, descending: Bool) -> Bool? {
        switch (lhs, rhs) {
        case (nil, nil): nil
        case (nil, _): false
        case (_, nil): true
        case let (lhs?, rhs?): lhs == rhs ? nil : (descending ? lhs > rhs : lhs < rhs)
        }
    }

    /// Finder's order ("feat-2" before "feat-10"); nil when the names are the same.
    static func precedes(name lhs: String, _ rhs: String) -> Bool? {
        switch lhs.localizedStandardCompare(rhs) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: nil
        }
    }
}
