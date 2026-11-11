import CleanCore
import Foundation

/// What the Tool caches sheet asks the person to confirm: the selected entries a scan made when the sheet opened
/// still finds ready, each with its size, folder, note and what it keeps, and the ones left alone with why.
/// `ToolCacheCleaner` checks every entry again right before it cleans it.
public struct CachesConfirmation: Identifiable, Sendable {
    public static let downloadsLine = "These are downloads and caches the tools fetch or rebuild when they need them "
        + "again. They're deleted for good, not moved to the Trash, and can't be restored from Recently removed. "
        + "Each one is checked again right before it's cleaned, and each cleanup is logged."

    public struct Item: Identifiable, Sendable, Hashable {
        public let id: String
        public let name: String
        public let folderText: String
        public let bytes: Int64?
        /// When it comes back (PLAN §4.6 copy).
        public let note: String
        /// What cleaning leaves alone.
        public let keeps: [String]
        /// Set only when the fresh scan found it ready: exactly what `ToolCacheCleaner` is given.
        public let finding: ToolCacheFinding?
        /// Why it is left alone; nil when it will be cleaned.
        public let leftAloneReason: String?

        public var isAllowed: Bool { finding != nil && leftAloneReason == nil }
        public var sizeText: String { DisplayText.bytes(bytes) }

        init(row: CacheRow?, id: String, name: String, leftAlone: String?) {
            self.id = id
            self.name = name
            folderText = row?.folderText ?? "–"
            bytes = row?.bytes
            note = row?.note ?? ""
            keeps = row?.keeps ?? []
            finding = leftAlone == nil ? row?.finding : nil
            leftAloneReason = leftAlone
        }
    }

    public let id = UUID()
    public let items: [Item]

    public init(items: [Item]) {
        self.items = items
    }

    public var allowed: [Item] { items.filter(\.isAllowed) }
    public var blocked: [Item] { items.filter { !$0.isAllowed } }
    public var estimatedTotalBytes: Int64 { allowed.compactMap(\.bytes).reduce(0, +) }
    public var estimatedSizeText: String { CleanupPresentation.estimate(allowed.map(\.bytes)) }
    public var hasUnknownSizes: Bool { allowed.contains { $0.bytes == nil } }

    /// "Clean npm", "Clean 3 items".
    public var cleanButtonTitle: String { CleanupPresentation.button("Clean", count: allowed.count) }
    public var title: String { CleanupPresentation.title("Clean", count: allowed.count, noun: "cache", plural: "caches", sizes: allowed.map(\.bytes)) }

}
