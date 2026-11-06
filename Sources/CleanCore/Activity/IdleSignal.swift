/// One of the four activity signals of PLAN §4.3.
public enum IdleSignal: String, Sendable, Codable, Hashable, CaseIterable {
    /// Committer date of HEAD.
    case headCommit
    /// mtime of `index` and `HEAD` in the worktree's git dir, and the time of the last `logs/HEAD` entry
    /// (not that file's mtime: `git gc` rewrites every reflog of a repo).
    case gitActivity
    /// Newest file mtime in the worktree, outside `.git` and regenerable folders.
    case fileChange
    /// Newest Claude Code transcript for the folder.
    case claudeTranscript

    public var label: String {
        switch self {
        case .headCommit: "last commit"
        case .gitActivity: "git activity"
        case .fileChange: "file change"
        case .claudeTranscript: "Claude transcript"
        }
    }
}
