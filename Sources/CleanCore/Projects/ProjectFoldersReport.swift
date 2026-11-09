/// What `ProjectFoldersScanner` found: one entry per checkout with light-clean candidates, and what the Claude
/// and Cursor worktrees it left out hold (PLAN §4.5).
public struct ProjectFoldersReport: Sendable, Hashable {
    public struct Total: Sendable, Hashable, Codable {
        public var count: Int
        public var bytes: Int64

        public init(count: Int, bytes: Int64) {
            self.count = count
            self.bytes = bytes
        }
    }

    /// Biggest first; ties keep the scan's order.
    public var projects: [ProjectFolders]
    /// Claude and Cursor worktrees with light-clean folders, and those folders' sizes added up. Not listed:
    /// removing them whole in Worktrees is the better action.
    public var leftOut: Total
    /// Checkouts that couldn't be looked at, one sentence each (a stale record, a folder git can't read).
    public var problems: [String]

    public init(projects: [ProjectFolders], leftOut: Total = Total(count: 0, bytes: 0), problems: [String] = []) {
        self.projects = Self.sorted(projects)
        self.leftOut = leftOut
        self.problems = problems
    }

    /// Every project, whatever its idle days.
    public var all: Total { Self.total(projects) }

    /// The projects "Select all idle" picks: idle known and at least `days`, nothing stopping a clean.
    public func ready(idleAtLeast days: Int) -> [ProjectFolders] {
        projects.filter { $0.status(threshold: days).isReady }
    }

    /// The "idle ≥ N days" total: what `ready(idleAtLeast:)` picks.
    public func idleTotal(atLeast days: Int) -> Total { Self.total(ready(idleAtLeast: days)) }

    /// This report with the projects at `paths` replaced by what `partial` found there (a project with nothing
    /// left to clean drops out). The left-out total stays.
    public func replacing(_ paths: Set<String>, with partial: ProjectFoldersReport) -> ProjectFoldersReport {
        let kept = projects.filter { !paths.contains($0.worktree.path) }
        let fresh = partial.projects.filter { paths.contains($0.worktree.path) }
        return ProjectFoldersReport(projects: kept + fresh, leftOut: leftOut, problems: problems + partial.problems)
    }

    public static func total(_ projects: [ProjectFolders]) -> Total {
        Total(count: projects.count, bytes: projects.reduce(0) { $0 + $1.totalBytes })
    }

    private static func sorted(_ projects: [ProjectFolders]) -> [ProjectFolders] {
        projects.enumerated()
            .sorted { ($0.element.totalBytes, $1.offset) > ($1.element.totalBytes, $0.offset) }
            .map(\.element)
    }
}
