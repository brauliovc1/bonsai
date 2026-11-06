import Foundation

/// Everything one scan found.
public struct ScanResult: Sendable, Codable, Equatable {
    /// The scan roots, as given.
    public var roots: [String]
    /// Main repo folders, sorted.
    public var repos: [String]
    /// Main checkouts and linked worktrees, grouped by repo (main first).
    public var worktrees: [Worktree]
    /// Estimated bytes per worktree path (`du -skx`). Missing when sizes were skipped, the folder is gone,
    /// or `du` failed. A main checkout's size leaves out linked worktrees nested inside it
    /// (`<repo>/.claude/worktrees/...`), so they are not counted twice.
    public var sizes: [String: Int64]
    /// Light-clean bytes per worktree path: the sum of `LightCleanFinder`'s candidate estimates. nil when
    /// not asked for (`Scanner.scan(includeDependencies:)`); a worktree is missing when it has no
    /// candidates with an estimate.
    public var dependencyBytes: [String: Int64]?
    public var issues: [ScanIssue]
    public var startedAt: Date
    /// Seconds.
    public var duration: TimeInterval

    public init(
        roots: [String],
        repos: [String],
        worktrees: [Worktree],
        sizes: [String: Int64],
        issues: [ScanIssue],
        startedAt: Date,
        duration: TimeInterval,
        dependencyBytes: [String: Int64]? = nil
    ) {
        self.roots = roots
        self.repos = repos
        self.worktrees = worktrees
        self.sizes = sizes
        self.issues = issues
        self.startedAt = startedAt
        self.duration = duration
        self.dependencyBytes = dependencyBytes
    }

    public func size(of worktree: Worktree) -> Int64? {
        sizes[worktree.path]
    }

    public func dependencyBytes(of worktree: Worktree) -> Int64? {
        dependencyBytes?[worktree.path]
    }

    /// At least one root was an existing folder. A scan where every root is missing found nothing on
    /// purpose, and scanning commands exit 1 for it.
    public var hasUsableRoot: Bool {
        let missing = Set(issues.filter { $0.kind == .rootMissing }.compactMap(\.path))
        return roots.contains { !missing.contains($0) }
    }

    public func worktrees(inRepo repoPath: String) -> [Worktree] {
        worktrees.filter { $0.repoPath == repoPath }
    }
}
