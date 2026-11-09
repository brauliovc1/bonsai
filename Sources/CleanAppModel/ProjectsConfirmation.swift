import CleanCore
import Foundation

/// What "Clean selected…" asks the user to confirm: for every selected project, the folders a fresh look found
/// (the light-clean sheet's own items, so `LightCleaner` gets exactly these), the idle days read again with a
/// note when they are below the threshold or unknown, and how to get the folders back.
public struct ProjectsConfirmation: Identifiable, Sendable {
    public struct Item: Identifiable, Sendable {
        /// The fresh look at the checkout (`LightCleanFlow.look`).
        public let lightClean: LightCleanConfirmation.Item
        /// The idle report read when the sheet opened.
        public let idle: IdleReport
        public let threshold: Int
        /// `RebuildHint`'s lines for the folders listed.
        public let rebuildLines: [String]

        public init(lightClean: LightCleanConfirmation.Item, idle: IdleReport, threshold: Int, rebuildLines: [String]) {
            self.lightClean = lightClean
            self.idle = idle
            self.threshold = threshold
            self.rebuildLines = rebuildLines
        }

        public var id: WorktreeRow.ID { lightClean.id }
        public var worktree: Worktree { lightClean.worktree }
        public var name: String { worktree.url.lastPathComponent }
        public var repoName: String { lightClean.repoName }
        public var candidates: [LightCleanCandidate] { lightClean.candidates }
        public var isCleanable: Bool { lightClean.isCleanable }
        public var estimatedBytes: Int64 { lightClean.estimatedBytes }

        /// Below the threshold: "You worked here N days ago; it will need a reinstall."; idle unknown: why it
        /// isn't one of the idle ones. nil when idle long enough.
        public var idleNote: String? {
            guard let days = idle.idleDays else {
                return "Bonsai couldn't tell when you last worked here; it will need a reinstall."
            }
            return days < threshold ? ProjectStatus.recentNote(days: days) : nil
        }
    }

    public let id = UUID()
    public let items: [Item]

    public init(items: [Item]) {
        self.items = items
    }

    /// The projects with folders to delete.
    public var cleanable: [Item] { items.filter(\.isCleanable) }
    /// The projects with nothing to delete now, shown after the others with why.
    public var others: [Item] { items.filter { !$0.isCleanable } }

    public var folderCount: Int { cleanable.reduce(0) { $0 + $1.candidates.count } }
    public var estimatedTotalBytes: Int64 { cleanable.reduce(0) { $0 + $1.estimatedBytes } }
    public var hasUnknownSizes: Bool { cleanable.contains { $0.lightClean.hasUnknownSizes } }

    /// "Clean 2 projects?" or "Nothing to delete".
    public var title: String {
        cleanable.isEmpty ? "Nothing to delete" : "Clean \(DisplayText.projects(cleanable.count))?"
    }

    /// "Delete 5 folders".
    public var deleteButtonTitle: String { "Delete \(DisplayText.folders(folderCount))" }

    /// "2 projects, 5 folders, about 1.2 GB (estimate)".
    public var summary: String {
        "\(DisplayText.projects(cleanable.count)), \(DisplayText.folders(folderCount)), about "
            + DisplayText.bytes(estimatedTotalBytes) + (hasUnknownSizes ? " (some sizes unknown)" : "") + " (estimate)"
    }
}
