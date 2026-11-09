/// One checkout on the Project folders screen (PLAN §4.5): its light-clean candidates from `LightCleanFinder`
/// with their sizes, the folders the finder left alone, its idle report, and what stops a clean now.
public struct ProjectFolders: Sendable, Hashable, Identifiable {
    public struct Folder: Sendable, Hashable {
        /// Made by `LightCleanFinder`; its `estimatedBytes` is nil when the size came from the cache.
        public var candidate: LightCleanCandidate
        /// The `du` estimate (from `sizes.json` when still valid); nil when it couldn't be measured.
        public var bytes: Int64?

        public init(candidate: LightCleanCandidate, bytes: Int64?) {
            self.candidate = candidate
            self.bytes = bytes ?? candidate.estimatedBytes
        }

        public var relativePath: String { candidate.relativePath }
        public var name: String { candidate.name }
    }

    /// git's record of the checkout as the scan listed it.
    public var worktree: Worktree
    /// For a main checkout, the most recent of its own and those of the linked worktrees inside it.
    public var idle: IdleReport
    /// Sorted by relative path.
    public var folders: [Folder]
    /// Folders found by name and left alone, with why.
    public var skipped: [LightCleanSkip]
    /// Folders the walk couldn't read.
    public var unreadable: [String]
    /// A process inside, or processes that couldn't be checked, when the scan looked.
    public var blocker: LightCleanSkipReason?
    /// "How to get them back" (`RebuildHint`).
    public var rebuildLines: [String]

    public init(
        worktree: Worktree,
        idle: IdleReport,
        folders: [Folder],
        skipped: [LightCleanSkip] = [],
        unreadable: [String] = [],
        blocker: LightCleanSkipReason? = nil,
        rebuildLines: [String] = []
    ) {
        self.worktree = worktree
        self.idle = idle
        self.folders = folders
        self.skipped = skipped
        self.unreadable = unreadable
        self.blocker = blocker
        self.rebuildLines = rebuildLines
    }

    public var id: String { worktree.path }
    public var idleDays: Int? { idle.idleDays }

    /// The folders' sizes added up (those with a size).
    public var totalBytes: Int64 { folders.compactMap(\.bytes).reduce(0, +) }
    public var hasUnknownSizes: Bool { folders.contains { $0.bytes == nil } }

    public func status(threshold: Int) -> ProjectStatus {
        ProjectStatus(idleDays: idleDays, blocker: blocker, threshold: threshold)
    }

    /// Idle at least `days` (idle known), whatever else holds.
    public func isIdle(atLeast days: Int) -> Bool {
        idleDays.map { $0 >= days } ?? false
    }
}
