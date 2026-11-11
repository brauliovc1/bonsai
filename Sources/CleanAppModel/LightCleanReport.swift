import Foundation

/// The light-clean sheet's second page: every worktree's outcome and the space freed in total.
public struct LightCleanReport: Sendable {
    public let outcomes: [LightCleanOutcome]

    public var deletedCount: Int { outcomes.reduce(0) { $0 + $1.deletedCount } }
    public var notDeletedCount: Int { outcomes.reduce(0) { $0 + $1.folders.count - $1.deletedCount } }

    /// Sum of the per-folder measurements over every worktree; nil when nothing was deleted or none could be read.
    public var measuredFreedBytes: Int64? {
        let measured = outcomes.compactMap(\.freedBytes)
        return measured.isEmpty ? nil : measured.reduce(0, +)
    }

    /// "Deleted 3 folders, freed 1.2 GB." plus what was left alone, if anything.
    public var summary: String {
        var text = "Nothing was deleted."
        if deletedCount > 0 {
            text = "Deleted \(DisplayText.folders(deletedCount))"
                + (measuredFreedBytes.map { ", freed \(DisplayText.bytes($0))" } ?? "") + "."
        }
        if notDeletedCount > 0 {
            text += " \(DisplayText.folders(notDeletedCount)) \(notDeletedCount == 1 ? "was" : "were") left alone."
        }
        return text
    }
    public var headline: String { CleanupPresentation.headline(measuredFreedBytes) }

}
