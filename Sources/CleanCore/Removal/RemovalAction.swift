/// What a cleanup did.
public enum RemovalAction: String, Sendable, Codable, Hashable {
    /// `git worktree remove`; can be restored from the kept branch or commit.
    case worktreeRemove
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
}
