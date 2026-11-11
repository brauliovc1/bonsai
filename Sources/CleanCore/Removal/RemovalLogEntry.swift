import Foundation

/// One line of `removals.jsonl`.
public struct RemovalLogEntry: Sendable, Codable, Hashable, Identifiable {
    public var id: UUID
    public var date: Date
    public var mode: RemovalMode
    public var action: RemovalAction
    public var repoPath: String
    public var path: String
    public var branch: String?
    public var headSha: String?
    public var kind: WorktreeKind?
    public var estimatedBytes: Int64?
    /// Measured from the volume's free space before and after.
    public var freedBytes: Int64?
    public var notes: [String]
    public var restoredAt: Date?
    public var trashPath: String?
    public var trashIdentity: DownloadIdentity?

    public init(
        id: UUID = UUID(),
        date: Date,
        mode: RemovalMode,
        action: RemovalAction,
        repoPath: String,
        path: String,
        branch: String? = nil,
        headSha: String? = nil,
        kind: WorktreeKind? = nil,
        estimatedBytes: Int64? = nil,
        freedBytes: Int64? = nil,
        notes: [String] = [],
        restoredAt: Date? = nil,
        trashPath: String? = nil,
        trashIdentity: DownloadIdentity? = nil
    ) {
        self.id = id
        self.date = Self.wholeSeconds(date)
        self.mode = mode
        self.action = action
        self.repoPath = repoPath
        self.path = path
        self.branch = branch
        self.headSha = headSha
        self.kind = kind
        self.estimatedBytes = estimatedBytes
        self.freedBytes = freedBytes
        self.notes = notes
        self.restoredAt = restoredAt.map(Self.wholeSeconds)
        self.trashPath = trashPath
        self.trashIdentity = trashIdentity
    }

    /// The log stores ISO 8601 dates to the second; entries keep the same precision in memory, so an
    /// entry read back equals the one written.
    public static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    /// A removed worktree that has not been put back yet.
    public var isRestorable: Bool { action.isWorktreeRemoval && restoredAt == nil }
}
