import CleanCore

/// The words of Remove anyway (PLAN §4.8, §8.4): the sheet's copy, each entry of the list, and what to do
/// instead when a blocker can't be overridden.
public enum RemoveAnywayText {
    public static let actionTitle = "Remove anyway…"
    public static let buttonTitle = "Remove anyway"
    public static let checkbox = "I understand these are deleted for good"
    /// PLAN §4.8, exact copy: the refusal when the re-check right before the delete found a difference.
    public static let changed = "It changed since you confirmed. Look again."
    public static let detailsHint = "Remove anyway is in the details panel."

    /// "Remove “feat/login” anyway?" (the branch, or the folder's name when detached).
    public static func title(for worktree: Worktree) -> String {
        "Remove \u{201C}\(worktree.branch ?? worktree.url.lastPathComponent)\u{201D} anyway?"
    }

    /// PLAN §4.8, exact copy (for a detached worktree the last sentence says there is no branch).
    public static func line(for worktree: Worktree) -> String {
        let kept = worktree.branch == nil ? "There's no branch to keep: it's detached." : "The branch is kept."
        return "These are deleted for good. Bonsai can't bring them back. \(kept)"
    }

    /// "Uncommitted or untracked files (3)".
    public static func heading(_ section: LossList.Section) -> String {
        "\(section.category.title) (\(section.entries.count))"
    }

    /// The tooltip of Remove anyway… where it is offered.
    public static func help(_ list: LossList) -> String {
        "Delete this worktree with what only it holds (you see the list and confirm first). " + list.summary
    }

    /// What to do instead when Remove anyway is never offered for `reason` (PLAN §4.8).
    public static func instead(for reason: SafetyReason) -> String {
        switch reason {
        case .mainCheckout:
            return WorktreeStatusText.repoFolderSentence
        case .missingFolder:
            return "Its folder is already gone; prune git's record of it instead."
        case .locked:
            return "It's locked. Unlock it with git worktree unlock first; Remove anyway never overrides a lock."
        case .inUse, .operationInProgress, .staleRecord:
            return WorktreeStatusText.sentence(for: reason)
        case .inUseUnknown:
            return "Bonsai couldn't check which apps work inside (lsof is missing), so it can't remove it anyway."
        case .gitError(let message):
            return "Bonsai can't list exactly what would be lost (\(message))."
        case .nestedCheckouts(let paths):
            let what = paths.count == 1 ? "Another worktree or submodule checkout lives" : "Other worktrees or submodule checkouts live"
            return "\(what) inside it (\(paths.joined(separator: ", "))), and Bonsai can't list what "
                + "\(paths.count == 1 ? "it holds" : "they hold"). Remove \(paths.count == 1 ? "that one" : "those") first."
        case .nestedSearchIncomplete:
            return "Bonsai couldn't finish looking inside, so it can't list everything that would be lost."
        case .uncommitted, .hiddenLocalEdits, .submodules, .nestedUnreadable, .nestedClones, .packageCopies,
             .localOnlyCommits, .reflogOnlyCommits, .stash, .ignoredUserFiles, .claudeSession, .recentlyActive,
             .idleUnknown:
            return WorktreeStatusText.sentence(for: reason)
        }
    }
}
