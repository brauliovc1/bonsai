/// What `DerivedDataCleaner.delete` did.
public struct DerivedDataDeletion: Sendable, Hashable {
    /// An orphan the re-check right before deleting said no to.
    public struct Refusal: Sendable, Hashable {
        public var orphan: OrphanedDerivedData
        public var reason: String
    }

    /// An orphan whose deletion started and failed (part of it may be gone).
    public struct Failure: Sendable, Hashable {
        public var orphan: OrphanedDerivedData
        public var message: String
    }

    public var deleted: [OrphanedDerivedData]
    public var refused: [Refusal]
    public var failed: [Failure]
    /// One log entry per deleted or failed folder, each written right after its delete.
    public var entries: [RemovalLogEntry]
    /// Things that went wrong after deleting (a log entry not written).
    public var warnings: [String]
    /// False when a log entry could not be written.
    public var logged: Bool
    /// Measured from the volume's free space around each delete, summed; nil when nothing was deleted or
    /// the volume could not be read.
    public var freedBytes: Int64?
}
