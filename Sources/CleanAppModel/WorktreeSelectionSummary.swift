import CleanCore
import Foundation

/// The details panel and the selection bar with several rows selected: how many, how big, how many can be
/// removed by hand.
public struct WorktreeSelectionSummary: Equatable, Sendable {
    public let count: Int
    public let repoCount: Int
    public let totalBytes: Int64?
    /// Rows a manual removal would accept (never a repo folder).
    public let removableCount: Int
    /// What those removable rows hold.
    public let removableBytes: Int64

    public init(rows: [WorktreeRow]) {
        count = rows.count
        repoCount = Set(rows.map(\.worktree.repoPath)).count
        let sizes = rows.compactMap(\.sizeBytes)
        totalBytes = sizes.isEmpty ? nil : sizes.reduce(0, +)
        let removable = rows.filter(\.canRemove)
        removableCount = removable.count
        removableBytes = removable.compactMap(\.sizeBytes).reduce(0, +)
    }

    /// "3 worktrees selected in 2 repos".
    public var title: String {
        let repos = repoCount == 1 ? "1 repo" : "\(repoCount) repos"
        return "\(DisplayText.worktrees(count)) selected in \(repos)"
    }

    /// "1.2 GB in total".
    public var sizeText: String { "\(DisplayText.bytes(totalBytes)) in total" }

    /// "2 can be removed; 1 can't."
    public var removableText: String {
        let others = count - removableCount
        let can = "\(removableCount) can be removed"
        guard others > 0 else { return can + "." }
        return can + "; \(others) can't."
    }
}
