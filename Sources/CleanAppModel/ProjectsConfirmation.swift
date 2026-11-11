import CleanCore
import Foundation

/// What "Clean selected…" asks the user to confirm: for every selected project, the folders a fresh look found
/// (the light-clean sheet's own items, so `LightCleaner` gets exactly these), the idle days read again with a
/// note when they are below the threshold or unknown, and how to get the folders back.
///
/// A project "Select all idle" picked that is no longer idle long enough (worked on since, or idle unknown now)
/// is not deleted: it is listed under "Changed since you selected it", unticked, and deleted only if the user
/// ticks it (`included`). A project picked by hand is deleted whatever its idle days, with the note (PLAN §4.5).
public struct ProjectsConfirmation: Identifiable, Sendable {
    public struct Item: Identifiable, Sendable {
        /// The fresh look at the checkout (`LightCleanFlow.look`).
        public let lightClean: LightCleanConfirmation.Item
        /// The idle report read when the sheet opened.
        public let idle: IdleReport
        public let threshold: Int
        /// `RebuildHint`'s lines for the folders listed.
        public let rebuildLines: [String]
        /// Picked by "Select all idle" rather than by hand.
        public let wasAutoPicked: Bool

        public init(
            lightClean: LightCleanConfirmation.Item,
            idle: IdleReport,
            threshold: Int,
            rebuildLines: [String],
            wasAutoPicked: Bool = false
        ) {
            self.lightClean = lightClean
            self.idle = idle
            self.threshold = threshold
            self.rebuildLines = rebuildLines
            self.wasAutoPicked = wasAutoPicked
        }

        public var id: WorktreeRow.ID { lightClean.id }
        public var worktree: Worktree { lightClean.worktree }
        public var name: String { worktree.url.lastPathComponent }
        public var repoName: String { lightClean.repoName }
        public var candidates: [LightCleanCandidate] { lightClean.candidates }
        /// Folders a light clean could delete now (whether they will depends on `changedSincePick`).
        public var hasFolders: Bool { lightClean.isCleanable }
        /// Picked by "Select all idle", and its idle days read now are below the threshold or unknown.
        public var changedSincePick: Bool {
            wasAutoPicked && hasFolders && (idle.idleDays.map { $0 < threshold } ?? true)
        }
        public var estimatedBytes: Int64 { lightClean.estimatedBytes }
        public var estimatedSizeText: String { lightClean.estimatedSizeText }

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
    /// Projects of `changed` the user ticked to delete anyway.
    public var included: Set<Item.ID> = []

    public init(items: [Item]) {
        self.items = items
    }

    /// The projects whose folders will be deleted: the ready ones and the ticked changed ones.
    public var cleanable: [Item] { items.filter { $0.hasFolders && (!$0.changedSincePick || included.contains($0.id)) } }
    /// The projects to delete that didn't change since they were picked.
    public var ready: [Item] { items.filter { $0.hasFolders && !$0.changedSincePick } }
    /// "Select all idle" picked them, and they are no longer idle long enough: not deleted unless ticked.
    public var changed: [Item] { items.filter(\.changedSincePick) }
    /// The projects with nothing to delete now, shown after the others with why.
    public var others: [Item] { items.filter { !$0.hasFolders } }

    public var folderCount: Int { cleanable.reduce(0) { $0 + $1.candidates.count } }
    public var estimatedTotalBytes: Int64 { cleanable.reduce(0) { $0 + $1.estimatedBytes } }
    public var estimatedSizeText: String { CleanupPresentation.estimate(cleanable.flatMap(\.candidates).map(\.estimatedBytes)) }
    public var hasUnknownSizes: Bool { cleanable.contains { $0.lightClean.hasUnknownSizes } }

    /// "Clean 2 projects?" or "Nothing to delete".
    public var title: String {
        CleanupPresentation.title("Clean", count: cleanable.count, noun: "project", sizes: cleanable.flatMap(\.candidates).map(\.estimatedBytes))
    }

    public var deleteButtonTitle: String { CleanupPresentation.button("Clean", count: folderCount) }

    /// "2 projects, 5 folders, at least 1.2 GB (estimate)" when some measurements are missing.
    public var summary: String {
        let amount = hasUnknownSizes ? estimatedSizeText : "about " + estimatedSizeText
        return "\(DisplayText.projects(cleanable.count)), \(DisplayText.folders(folderCount)), \(amount) (estimate)"
    }
}
