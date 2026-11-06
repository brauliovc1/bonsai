import Foundation

/// Where a worktree lives (PLAN §3 "Kinds").
public enum WorktreeKind: String, Sendable, Codable, Hashable, CaseIterable {
    /// The repo's main checkout (first porcelain record).
    case main
    /// Made by the Claude app: the path contains `/.claude/worktrees/`.
    case claude
    /// Made by Cursor: under `~/.cursor/worktrees/`.
    case cursor
    /// In the same parent folder as the main checkout, e.g. `<repo>-<task>`.
    case sibling
    case other

    /// Classifies a worktree. Paths are compared after standardizing and resolving symlinks, so
    /// `/tmp/x` and `/private/tmp/x` are the same folder.
    public static func classify(
        path: URL,
        isMain: Bool,
        mainPath: URL,
        cursorWorktreesDirectory: URL
    ) -> WorktreeKind {
        if isMain { return .main }
        let canonical = CanonicalPath.resolve(path)
        let claudeMarker = "/.claude/worktrees/"
        if path.standardized.path.contains(claudeMarker) || canonical.contains(claudeMarker) { return .claude }
        if CanonicalPath.isInside(path, directory: cursorWorktreesDirectory) { return .cursor }
        let parent = (canonical as NSString).deletingLastPathComponent
        let mainParent = (CanonicalPath.resolve(mainPath) as NSString).deletingLastPathComponent
        if parent == mainParent { return .sibling }
        return .other
    }
}
