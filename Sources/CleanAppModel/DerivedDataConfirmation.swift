import CleanCore
import Foundation

/// What the DerivedData sheet asks the user to confirm: the selected folders that a scan made when the sheet
/// opened still finds orphaned, and the ones that are not orphaned any more (or are gone), left alone.
/// `DerivedDataCleaner` checks each orphan again right before it deletes it.
public struct DerivedDataConfirmation: Identifiable, Sendable {
    public static let permanentLine = "These folders are deleted for good, not moved to the Trash, and can't be "
        + "restored from Recently removed. Xcode builds them again the next time the project is built. "
        + "Each deletion is logged."

    public struct Item: Identifiable, Sendable, Hashable {
        /// The folder's absolute path.
        public let folder: String
        public let name: String
        /// What the fresh scan found: nil when the folder is gone.
        public let state: DerivedDataState?
        public let workspacePath: String?
        public let bytes: Int64?
        /// Set only when the fresh scan found it orphaned: exactly what `DerivedDataCleaner` is given.
        public let orphan: OrphanedDerivedData?
        /// Why it is left alone; nil when it will be deleted.
        public let leftAloneReason: String?

        public var id: String { folder }
        public var isAllowed: Bool { orphan != nil && leftAloneReason == nil }
        public var sizeText: String { DisplayText.bytes(bytes) }
    }

    public let id = UUID()
    public let root: String
    /// Why the root is refused (`/`, the home folder or above it, not a folder): nothing is deleted then.
    public let refusal: String?
    public let items: [Item]

    public init(root: String, refusal: String?, items: [Item]) {
        self.root = root
        self.refusal = refusal
        self.items = items
    }

    public var allowed: [Item] { items.filter(\.isAllowed) }
    public var blocked: [Item] { items.filter { !$0.isAllowed } }
    public var estimatedTotalBytes: Int64 { allowed.compactMap(\.bytes).reduce(0, +) }
    public var estimatedSizeText: String { CleanupPresentation.estimate(allowed.map(\.bytes)) }
    public var hasUnknownSizes: Bool { allowed.contains { $0.bytes == nil } }

    /// "Delete 2 folders".
    public var deleteButtonTitle: String { CleanupPresentation.button("Delete", count: allowed.count) }
    public var title: String { CleanupPresentation.title("Delete", count: allowed.count, noun: "folder", sizes: allowed.map(\.bytes)) }

}
