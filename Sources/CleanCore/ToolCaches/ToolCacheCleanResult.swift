import Foundation

/// What `ToolCacheCleaner.clean` did.
public struct ToolCacheCleanResult: Sendable, Hashable {
    /// An entry whose cleaning started; `failures` lists what couldn't be removed (part of it may remain).
    public struct Cleaned: Sendable, Hashable {
        public var id: String
        public var name: String
        /// How many items went: top-level children, version folders, or the backup.
        public var removedCount: Int
        public var estimatedBytes: Int64?
        /// Free space after minus before this entry; nil when the volume couldn't be read.
        public var freedBytes: Int64?
        public var failures: [String]

        /// Nothing went and something failed.
        public var isFailure: Bool { removedCount == 0 && !failures.isEmpty }
    }

    /// An entry the check right before it said no to; nothing of it was touched.
    public struct Refused: Sendable, Hashable {
        public var id: String
        public var name: String
        public var reason: String
    }

    public var cleaned: [Cleaned] = []
    public var refused: [Refused] = []
    /// One log entry per cleaned entry, each written right after the entry.
    public var entries: [RemovalLogEntry] = []
    /// Things that went wrong after cleaning (a log entry not written).
    public var warnings: [String] = []
    /// False when a log entry could not be written.
    public var logged = true
    /// Measured around each entry and summed; nil when nothing was cleaned or the volume couldn't be read.
    public var freedBytes: Int64?

    public init() {}

    /// Entries where something couldn't be removed.
    public var failedCount: Int { cleaned.filter { !$0.failures.isEmpty }.count }
}
