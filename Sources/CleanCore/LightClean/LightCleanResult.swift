/// What `LightCleaner.clean` did.
public struct LightCleanResult: Sendable, Hashable {
    /// A candidate whose deletion started and failed (part of it may be gone).
    public struct Failure: Sendable, Hashable {
        public var candidate: LightCleanCandidate
        public var message: String
    }

    /// The worktree as git lists it now.
    public var worktree: Worktree
    public var deleted: [LightCleanCandidate]
    /// Candidates the re-check right before deleting said no to.
    public var refused: [LightCleanSkip]
    public var failed: [Failure]
    /// One log entry per deleted or failed folder, each written right after its delete.
    public var entries: [RemovalLogEntry]
    /// Things that went wrong after deleting (a log entry not written).
    public var warnings: [String]
    /// Measured from the volume's free space around each delete, summed; nil when nothing was deleted or
    /// the volume could not be read.
    public var freedBytes: Int64?

    /// False when a log entry could not be written.
    public var logged: Bool
}
