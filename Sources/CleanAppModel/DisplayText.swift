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
}
