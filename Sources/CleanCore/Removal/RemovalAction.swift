/// What a cleanup did.
public enum RemovalAction: String, Sendable, Codable, Hashable {
    /// `git worktree remove`; can be restored from the kept branch or commit.
    case worktreeRemove
    /// "Remove anyway" (PLAN §4.8): `git worktree remove --force` by hand, one worktree; the loss list is in
    /// `notes`. Restored like `worktreeRemove`, without what was lost.
    case worktreeRemoveAnyway
    /// `git worktree prune` for one repo; the pruned names are in `notes`.
    case worktreePrune
    /// Light clean of one worktree (PLAN §4.2); the deleted and refused folders are in `notes`. Not restorable.
    case lightClean
    /// Orphaned Xcode DerivedData folders deleted (PLAN §4.4); folder names and project paths in `notes`.
    case derivedDataDelete
    /// `docker system prune -f`; the command is in `notes`.
    case dockerPrune
    /// `xcrun simctl delete unavailable`; the command is in `notes`.
    case simulatorsDeleteUnavailable
    /// One tool-cache entry cleaned (PLAN §4.6): `repoPath` is the catalog entry id (`npm`), `path` its folder,
    /// what was removed in `notes`. Not restorable.
    case cacheClean
    /// A confirmed old download moved with the system Trash operation.
    case movedToTrash
    /// A previously trashed download moved back without replacing another file.
    case putBack
    /// Finder emptied the Trash after the user's confirmation.
    case trashEmptied

    /// A worktree removal of either kind: restorable from its branch or commit.
    public var isWorktreeRemoval: Bool {
        self == .worktreeRemove || self == .worktreeRemoveAnyway
    }
}
