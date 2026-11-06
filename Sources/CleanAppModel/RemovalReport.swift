import Foundation

/// The sheet's second page: every outcome and the space freed in total.
public struct RemovalReport: Sendable {
    public let outcomes: [RemovalOutcome]
    /// Free space after the batch minus before it (never negative), summed over every volume something was
    /// removed from; nil when nothing was removed or no such volume could be read.
    public let measuredFreedBytes: Int64?

    public var removedCount: Int { outcomes.filter(\.removed).count }
    public var failedCount: Int { outcomes.count - removedCount }
    public var changedCount: Int { outcomes.filter(\.changedSinceConfirmed).count }

    /// "Removed 2 worktrees, freed 20.0 MB." plus what was left alone, if anything.
    public var summary: String {
        var text = "Nothing was removed."
        if removedCount > 0 {
            text = "Removed \(DisplayText.worktrees(removedCount))"
                + (measuredFreedBytes.map { ", freed \(DisplayText.bytes($0))" } ?? "") + "."
        }
        if changedCount > 0 {
            let them = changedCount == 1 ? "it" : "them"
            text += " \(changedCount) changed since you confirmed \(them) and \(changedCount == 1 ? "was" : "were") "
                + "left alone; review \(them) again."
        }
        let otherFailures = failedCount - changedCount
        if otherFailures > 0 { text += " \(DisplayText.worktrees(otherFailures)) not removed." }
        return text
    }
}
