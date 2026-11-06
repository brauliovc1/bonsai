import CleanCore
import Foundation

/// What the light-clean sheet asks the user to confirm: for every selected worktree, the folders that would
/// be deleted (found afresh when the sheet opened), the folders left alone with their reasons, and the
/// worktrees that can't be light-cleaned now. `LightCleaner` checks every folder again right before it
/// deletes it, and deletes only the ones listed here.
public struct LightCleanConfirmation: Identifiable, Sendable {
    public static let nextTimeLine = "Next time you use it, run npm ci / pod install / flutter pub get as needed."
    public static let permanentLine = "These folders are deleted for good, not moved to the Trash, and can't be "
        + "restored from Recently removed. Each deletion is logged."

    public struct Item: Identifiable, Sendable {
        /// git's current record of the worktree, read when the sheet opened.
        public let worktree: Worktree
        /// nil when the worktree could not be looked at.
        public let findings: LightCleanFindings?
        /// Why nothing in this worktree is touched now (stale record, process inside, can't be listed).
        public let blocker: String?

        public init(worktree: Worktree, findings: LightCleanFindings?, blocker: String?) {
            self.worktree = worktree
            self.findings = findings
            self.blocker = blocker
        }

        public var id: WorktreeRow.ID { WorktreeRow.ID(worktree) }
        public var repoName: String { DisplayText.repoName(worktree.repoPath) }
        public var branchText: String { DisplayText.branch(of: worktree) }

        /// The folders that will be deleted; empty when the worktree is left alone.
        public var candidates: [LightCleanCandidate] {
            blocker == nil ? findings?.candidates ?? [] : []
        }
        /// Folders found by name and left alone, with why.
        public var skipped: [LightCleanSkip] { findings?.skipped ?? [] }
        public var unreadable: [String] { findings?.unreadable ?? [] }
        public var isCleanable: Bool { !candidates.isEmpty }
        public var estimatedBytes: Int64 { candidates.compactMap(\.estimatedBytes).reduce(0, +) }
        public var hasUnknownSizes: Bool { candidates.contains { $0.estimatedBytes == nil } }

        /// Why this worktree has nothing to delete: the blocker, the finder's problem, or just no folders.
        public var leftAloneReason: String? {
            if let blocker { return blocker }
            if let problem = findings?.problem { return "Can't be looked at: \(problem)." }
            guard candidates.isEmpty else { return nil }
            return skipped.isEmpty ? "No dependency or build folders to delete." : "Every folder found here is left alone."
        }
    }

    public let id = UUID()
    public let items: [Item]

    public init(items: [Item]) {
        self.items = items
    }

    /// The worktrees with folders to delete.
    public var cleanable: [Item] { items.filter(\.isCleanable) }
    /// The worktrees with nothing to delete or left alone, shown after the others.
    public var others: [Item] { items.filter { !$0.isCleanable } }

    public var folderCount: Int { cleanable.reduce(0) { $0 + $1.candidates.count } }
    /// The `du` estimate of every listed folder. Freed space is measured afterwards and can be lower.
    public var estimatedTotalBytes: Int64 { cleanable.reduce(0) { $0 + $1.estimatedBytes } }
    public var hasUnknownSizes: Bool { cleanable.contains(where: \.hasUnknownSizes) }

    /// "Delete 3 folders".
    public var deleteButtonTitle: String { "Delete \(DisplayText.folders(folderCount))" }
}
