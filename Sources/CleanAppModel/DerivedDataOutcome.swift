import CleanCore
import Foundation

/// What happened to one confirmed DerivedData folder.
public struct DerivedDataOutcome: Identifiable, Sendable {
    public enum Status: Sendable, Hashable {
        /// `freedBytes`: free space after minus before this delete; nil when the volume couldn't be read.
        case deleted(freedBytes: Int64?)
        /// The re-check right before deleting said no (its project is back, it changed, the root is refused).
        case refused(String)
        case failed(String)
    }

    public let item: DerivedDataConfirmation.Item
    public let status: Status

    public var id: String { item.id }
    public var isDeleted: Bool {
        if case .deleted = status { return true }
        return false
    }
}

/// The DerivedData sheet's second page.
public struct DerivedDataCleanupReport: Sendable {
    public let outcomes: [DerivedDataOutcome]
    /// Measured from the volume around each delete, summed; nil when nothing was deleted or it couldn't be read.
    public let measuredFreedBytes: Int64?
    /// Things that went wrong after deleting (a log entry not written).
    public let warnings: [String]

    public var deletedCount: Int { outcomes.filter(\.isDeleted).count }
    public var notDeletedCount: Int { outcomes.count - deletedCount }

    /// "Deleted 2 folders, freed 1.2 GB." plus what was left alone, if anything.
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
}
