import CleanCore
import Foundation

/// What happened to one confirmed item: removed (with `Remover`'s result) or not (with the reason).
public struct RemovalOutcome: Identifiable, Sendable {
    public let item: RemovalConfirmation.Item
    /// nil when nothing was removed.
    public let result: RemovalResult?
    /// Why nothing was removed: the worktree changed since it was confirmed, the re-check refused, or git did.
    public let error: String?
    /// Refused because it changed since the sheet showed it; the person should look at it again.
    public let changedSinceConfirmed: Bool

    init(item: RemovalConfirmation.Item, result: RemovalResult?, error: String?, changedSinceConfirmed: Bool = false) {
        self.item = item
        self.result = result
        self.error = error
        self.changedSinceConfirmed = changedSinceConfirmed
    }

    public var id: WorktreeRow.ID { item.id }
    public var removed: Bool { result != nil }
    /// Measured from the volume's free space before and after this one removal.
    public var freedBytes: Int64? { result?.freedBytes }
    /// Things that went wrong after git removed it (folder still there, log not written).
    public var warnings: [String] { result?.warnings ?? [] }
}
