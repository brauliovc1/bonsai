import CleanCore
import Foundation

/// What happened to one confirmed item: removed (with `Remover`'s result) or not (with the reason).
public struct RemovalOutcome: Identifiable, Sendable {
    public let item: RemovalConfirmation.Item
    /// nil when nothing was removed.
    public let result: RemovalResult?
    /// Why nothing was removed: the re-check refused, or git did.
    public let error: String?

    public var id: String { item.id }
    public var removed: Bool { result != nil }
    /// Measured from the volume's free space before and after this one removal.
    public var freedBytes: Int64? { result?.freedBytes }
    /// Things that went wrong after git removed it (folder still there, log not written).
    public var warnings: [String] { result?.warnings ?? [] }
}
