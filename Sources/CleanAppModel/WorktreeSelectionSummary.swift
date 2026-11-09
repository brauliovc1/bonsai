import CleanCore
import Foundation

/// The details panel with several rows selected: how many, how big, how many can be removed by hand.
public struct WorktreeSelectionSummary: Equatable, Sendable {
    public let count: Int
    public let repoCount: Int
    public let totalBytes: Int64?
    /// Rows a manual removal would accept (SAFE, AUTO-READY, and allowed with notes).
    public let removableCount: Int

    public init(rows: [WorktreeRow]) {
        count = rows.count
        repoCount = Set(rows.map(\.worktree.repoPath)).count
        let sizes = rows.compactMap(\.sizeBytes)
        totalBytes = sizes.isEmpty ? nil : sizes.reduce(0, +)
        removableCount = rows.filter(\.canRemove).count
    }

    /// "3 worktrees selected in 2 repos".
    public var title: String {
        let repos = repoCount == 1 ? "1 repo" : "\(repoCount) repos"
        return "\(DisplayText.worktrees(count)) selected in \(repos)"
    }

    /// "1.2 GB in total".
    public var sizeText: String { "\(DisplayText.bytes(totalBytes)) in total" }

    /// "2 can be removed by hand; 1 is blocked."
    public var removableText: String {
        let blocked = count - removableCount
        let can = removableCount == 1 ? "1 can be removed by hand" : "\(removableCount) can be removed by hand"
        guard blocked > 0 else { return can + "." }
        return can + "; \(blocked) \(blocked == 1 ? "is" : "are") blocked."
    }
}
