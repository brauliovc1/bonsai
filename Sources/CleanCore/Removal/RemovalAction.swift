/// What a cleanup did. Later phases add cases (light clean, DerivedData, docker prune, simulators).
public enum RemovalAction: String, Sendable, Codable, Hashable {
    /// `git worktree remove`; can be restored from the kept branch or commit.
    case worktreeRemove
    /// `git worktree prune` for one repo; the pruned names are in `notes`.
    case worktreePrune
}
