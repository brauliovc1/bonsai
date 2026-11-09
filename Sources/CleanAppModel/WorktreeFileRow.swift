import CleanCore
import Foundation

/// One file of a worktree as the details panel's "Unsaved changes" and the Remove anyway list show it: a plain word
/// for its state and its path relative to the worktree. Read-only: the actions on it (Show in Finder, Open, Copy
/// path) never change it; Open only where it can't run anything (`FileOpening`); a deleted file offers Copy path only.
public struct WorktreeFileRow: Identifiable, Hashable, Sendable {
    /// "Modified", "New", "Deleted", "Renamed"; "Hidden edit" and "Ignored" in the Remove anyway list.
    public let word: String
    /// Relative to the worktree, as git listed it.
    public let path: String
    /// "from old.txt" for a rename or copy.
    public let detail: String?
    public let url: URL
    /// Nothing is at the path (deleted, or gone since the scan): only its path can be copied.
    public let isGone: Bool
    /// How "Open" opens it; `.finderOnly` = no Open (`FileOpening`).
    public let opening: FileOpening

    public var id: String { path }

    init(word: String, path: String, detail: String?, in worktree: URL) {
        self.word = word
        self.path = path
        self.detail = detail
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        url = worktree.appending(path: trimmed, directoryHint: path.hasSuffix("/") ? .isDirectory : .inferFromPath)
        // lstat: a symlink is there even when what it points to isn't.
        isGone = (try? FileManager.default.attributesOfItem(atPath: url.path)) == nil
        opening = isGone ? .finderOnly : FileOpening.way(for: url)
    }

    /// An entry of `git status`.
    public init(_ entry: GitStatusEntry, in worktree: URL) {
        let detail = entry.change == .renamed || entry.change == .copied ? entry.from.map { "from \($0)" } : nil
        self.init(word: entry.change.rawValue, path: entry.path, detail: detail, in: worktree)
    }

    /// The full path, for Copy path and tooltips.
    public var fullPath: String { url.path }

    /// The rows of a Remove anyway list section that lists files (uncommitted files, hidden edits, files in a
    /// submodule folder, ignored files); nil for the others (repos, commits, notes).
    public static func rows(for section: LossList.Section, in worktree: URL) -> [WorktreeFileRow]? {
        switch section.category {
        case .uncommittedFiles:
            return section.entries.map { entry in
                entry.status.map { WorktreeFileRow($0, in: worktree) }
                    ?? WorktreeFileRow(word: entry.detail ?? "Changed", path: entry.text, detail: nil, in: worktree)
            }
        case .hiddenEdits:
            return section.entries.map { WorktreeFileRow(word: "Hidden edit", path: $0.text, detail: nil, in: worktree) }
        case .ignoredFiles:
            return section.entries.map { WorktreeFileRow(word: "Ignored", path: $0.text, detail: nil, in: worktree) }
        case .submoduleFiles:
            return section.entries.map { WorktreeFileRow(word: "Not in git", path: $0.text, detail: nil, in: worktree) }
        case .reposWithLocalWork, .unreadableRepos, .submodules, .unpushedCommits, .unreachableCommits, .commitsOnBranch,
             .stashes, .claudeSession:
            return nil
        }
    }
}
