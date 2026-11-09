import CleanCore
import Foundation

/// The Last commit and Folder columns, the remotes, the idle signals and what search looks at.
extension WorktreeRow {
    /// The subject on one line, or "–".
    public var lastCommitText: String { lastCommit?.subject ?? "–" }
    /// "3d ago", or "" without a last commit.
    public var lastCommitAgoText: String { lastCommit.map { DisplayText.ago($0.date, now: now) } ?? "" }
    /// The tooltip: the whole message, then author, date and short hash.
    public var lastCommitHelp: String {
        guard let commit = lastCommit else { return "No commit found" }
        return "\(commit.message)\n\n\(DisplayText.commitByline(commit))"
    }
    public var lastCommitSortKey: Date { lastCommit?.date ?? .distantPast }

    /// Every idle signal that was found, with its date, in PLAN §4.3's order.
    public var idleSignals: [(signal: IdleSignal, date: Date)] {
        IdleSignal.allCases.compactMap { signal in assessment.idle.signals[signal].map { (signal, $0) } }
    }

    /// What the search box matches: repo, branch, path, folder, remotes and the last commit's message.
    var searchableTexts: [String] {
        [repoName, branchText, path, folderText, lastCommit?.message ?? ""]
            + remotes.flatMap { [$0.url, $0.pushURL ?? "", RemoteURL.short($0.url)] }
    }

    /// Changes whenever what the details panel loads would: another worktree, or HEAD or the branch moved.
    public var detailsKey: String {
        [worktree.repoPath, worktree.path, worktree.head ?? "-", worktree.branch ?? "-"].joined(separator: "\u{1F}")
    }
}
