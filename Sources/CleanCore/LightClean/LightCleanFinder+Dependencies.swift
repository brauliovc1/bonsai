extension LightCleanFinder {
    /// Light-clean bytes per worktree path: the sum of each worktree's candidate estimates. Bare entries,
    /// missing folders and worktrees without measured candidates are left out. Every worktree in the list
    /// counts as known for the nested-checkout rule.
    public func dependencyBytes(
        of worktrees: [Worktree],
        maxConcurrentWorktrees: Int = 2,
        onFinished: @Sendable (_ completed: Int, _ total: Int) -> Void = { _, _ in }
    ) async -> [String: Int64] {
        let total = worktrees.count
        let sums = await BoundedConcurrency.map(
            worktrees,
            limit: maxConcurrentWorktrees,
            onCompletion: { onFinished($0, total) }
        ) { worktree -> Int64? in
            let findings = await candidates(in: worktree, knownWorktrees: worktrees)
            let estimates = findings.candidates.compactMap(\.estimatedBytes)
            return estimates.isEmpty ? nil : estimates.reduce(0, +)
        }
        var bytes: [String: Int64] = [:]
        for (worktree, sum) in zip(worktrees, sums) {
            if let sum { bytes[worktree.path] = sum }
        }
        return bytes
    }
}
