import Foundation

/// The sheet's second page: every outcome and the space freed in total.
public struct RemovalReport: Sendable {
    public let outcomes: [RemovalOutcome]
    /// The volume's free space after the batch minus before it (never negative); nil when unreadable.
    public let measuredFreedBytes: Int64?

    public var removedCount: Int { outcomes.filter(\.removed).count }
    public var failedCount: Int { outcomes.count - removedCount }

    /// "Removed 2 worktrees, freed 20.0 MB." plus the failures, if any.
    public var summary: String {
        var text = "Removed \(DisplayText.worktrees(removedCount))"
        if let measuredFreedBytes { text += ", freed \(DisplayText.bytes(measuredFreedBytes))" }
        text += "."
        if failedCount > 0 { text += " \(DisplayText.worktrees(failedCount)) not removed." }
        return text
    }
}
