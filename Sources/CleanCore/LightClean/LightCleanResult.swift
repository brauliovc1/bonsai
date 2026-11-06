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
    /// The log entry; nil when nothing was deleted or attempted (nothing is logged then).
    public var entry: RemovalLogEntry?
    /// Things that went wrong after deleting (the log not written).
    public var warnings: [String]

    /// Measured from the volume's free space; nil when nothing was deleted or the volume could not be read.
    public var freedBytes: Int64? { entry?.freedBytes }

    /// False when something was deleted but the log entry could not be written.
    public var logged: Bool
}
