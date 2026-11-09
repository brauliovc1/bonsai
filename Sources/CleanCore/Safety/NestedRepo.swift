/// A repo inside a worktree that `git worktree remove` would delete with it, and what was found in it
/// (PLAN §4.1 "Nested checkouts", §4.8): its local work ("2 unsaved changes", "1 stash"), or, for a repo git
/// can't read, git's first error line.
public struct NestedRepo: Sendable, Hashable, Codable {
    /// Relative to the worktree.
    public var path: String
    public var findings: [String]

    public init(path: String, findings: [String]) {
        self.path = path
        self.findings = findings
    }

    /// "vendor/lib (2 unsaved changes, 1 stash)".
    public var description: String {
        findings.isEmpty ? path : "\(path) (\(findings.joined(separator: ", ")))"
    }
}
