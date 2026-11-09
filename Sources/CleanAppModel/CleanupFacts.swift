import CleanCore

/// What cleanups found out about checkouts after a scan may already have looked at them: sizes measured again
/// and worktrees removed, each with the scan generation current when it was found out. A scan that began no later
/// than that (it may have measured before the cleanup) ends with these applied again; a scan that began later saw
/// them itself, so they are dropped.
struct CleanupFacts {
    struct Key: Hashable {
        var repoPath: String
        var path: String

        init(_ worktree: Worktree) {
            repoPath = worktree.repoPath
            path = worktree.path
        }
    }

    /// Path -> its size measured after a cleanup (nil: the folder was gone).
    private(set) var sizes: [String: (generation: Int, bytes: Int64?)] = [:]
    private(set) var removed: [Key: Int] = [:]

    mutating func measured(_ bytes: [String: Int64?], generation: Int) {
        for (path, size) in bytes { sizes[path] = (generation, size) }
    }

    mutating func removed(_ worktrees: [Worktree], generation: Int) {
        for worktree in worktrees { removed[Key(worktree)] = generation }
    }

    /// Keeps only what a scan of `generation` can't have seen: facts found out while it, or an earlier one, ran.
    mutating func keepUnseen(byScan generation: Int) {
        sizes = sizes.filter { $0.value.generation >= generation }
        removed = removed.filter { $0.value >= generation }
    }
}
