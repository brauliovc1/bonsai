/// What `LightCleanFinder` found in one worktree.
public struct LightCleanFindings: Sendable, Hashable, Encodable {
    public var worktree: Worktree
    /// Folders that pass every condition, sorted by relative path.
    public var candidates: [LightCleanCandidate]
    /// Folders found by name and left alone, sorted by relative path.
    public var skipped: [LightCleanSkip]
    /// Folders the walk could not read; nothing below them was looked at.
    public var unreadable: [String]
    /// Why the worktree itself could not be looked at (bare entry, folder gone); nil normally.
    public var problem: String?

    public init(
        worktree: Worktree,
        candidates: [LightCleanCandidate] = [],
        skipped: [LightCleanSkip] = [],
        unreadable: [String] = [],
        problem: String? = nil
    ) {
        self.worktree = worktree
        self.candidates = candidates
        self.skipped = skipped
        self.unreadable = unreadable
        self.problem = problem
    }

    /// Sum of the candidates' estimates (those that have one).
    public var estimatedBytes: Int64 {
        candidates.compactMap(\.estimatedBytes).reduce(0, +)
    }
}
