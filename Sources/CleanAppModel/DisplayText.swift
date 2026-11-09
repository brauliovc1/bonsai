import CleanCore
import Foundation

/// The short texts the app shows in table cells, kept in one place so every screen words them alike.
public enum DisplayText {
    /// "20.0 MB", or "–" when unknown.
    public static func bytes(_ bytes: Int64?) -> String {
        bytes.map(ByteFormatting.string) ?? "–"
    }

    /// The branch, or "detached at 1a2b3c4d".
    public static func branch(of worktree: Worktree) -> String {
        if let branch = worktree.branch { return branch }
        if worktree.isBare { return "(bare)" }
        return "detached at \(worktree.head.map { String($0.prefix(8)) } ?? "?")"
    }

    /// "45d"; "–" for a main checkout or a missing folder; "unknown" when the idle clock couldn't tell.
    public static func idle(_ assessment: WorktreeAssessment) -> String {
        if assessment.worktree.isMain || assessment.safety.blockers.contains(.missingFolder) { return "–" }
        return assessment.idle.idleDays.map { "\($0)d" } ?? "unknown"
    }

    /// "1 worktree", "3 worktrees".
    public static func worktrees(_ count: Int) -> String {
        count == 1 ? "1 worktree" : "\(count) worktrees"
    }

    /// "1 folder", "3 folders".
    public static func folders(_ count: Int) -> String {
        count == 1 ? "1 folder" : "\(count) folders"
    }

    /// Where a running scan is. nil progress while scanning = the safety checks after the listing.
    public static func progress(_ progress: ScanProgress?) -> String {
        switch progress {
        case .discoveringRepos: "Finding repos…"
        case .listingWorktrees(let completed, let total): "Listing worktrees (\(completed) of \(total) repos)…"
        case .measuringSizes(let completed, let total): "Measuring sizes (\(completed) of \(total))…"
        case .finished, nil: "Checking each worktree…"
        }
    }

    /// The last path component of a repo path.
    public static func repoName(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    /// "just now", "12m ago", "5h ago", "3d ago", "2y ago"; "in the future" for a date more than a minute ahead
    /// (a clock that was wrong when the commit was made).
    public static func ago(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < -60 { return "in the future" }
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))h ago" }
        let days = Int(seconds / 86_400)
        return days < 365 ? "\(days)d ago" : "\(days / 365)y ago"
    }

    /// "Ana Pérez · 8 Nov 2026 at 14:05 · 1a2b3c4d".
    public static func commitByline(_ commit: CommitSummary) -> String {
        [commit.author, date(commit.date), commit.shortSHA].joined(separator: " · ")
    }

    /// A date and time as the details panel shows them.
    public static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// The first remote shortened, "+N" for the others ("github.com/me/app +1"); nil without remotes.
    public static func remotes(_ remotes: [GitRemote], home: URL?) -> String? {
        guard let first = remotes.first else { return nil }
        let short = RemoteURL.short(first.url, home: home)
        return remotes.count == 1 ? short : "\(short) +\(remotes.count - 1)"
    }
}
