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
    /// The log entry; nil when nothing was deleted or attempted (nothing is logged then).
    public var entry: RemovalLogEntry?
    /// Things that went wrong after deleting (the log not written).
    public var warnings: [String]
    /// False when something was deleted but the log entry could not be written.
    public var logged: Bool

    /// Measured from the volume's free space; nil when nothing was deleted or the volume could not be read.
    public var freedBytes: Int64? { entry?.freedBytes }
}
