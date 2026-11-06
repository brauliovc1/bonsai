/// What `Remover.remove` did.
public struct RemovalResult: Sendable, Hashable {
    /// The log entry (also when appending it to the log failed: see `warnings`).
    public var entry: RemovalLogEntry
    /// The verdict re-checked right before removing.
    public var safety: SafetyReport
    /// Measured from the volume's free space; nil when it could not be read.
    public var freedBytes: Int64? { entry.freedBytes }
    /// Things that went wrong after git removed the worktree (folder still there, log not written).
    public var warnings: [String]
    public var logged: Bool

    public init(entry: RemovalLogEntry, safety: SafetyReport, warnings: [String], logged: Bool) {
        self.entry = entry
        self.safety = safety
        self.warnings = warnings
        self.logged = logged
    }
}
