import Foundation

/// Metrics survive refreshes only while the two immutable commit IDs remain the same.
public actor BranchMap {
    struct Key: Hashable { let base: String; let tip: String }
    var cache: [Key: BranchMapMetrics] = [:]
    var pending: [Key: Task<BranchMapMetrics, Never>] = [:]
    var computations = 0
    var cacheHits = 0
    public static let concurrency = 4
    public static let dotLimit = 64
    static let unrelated = "No common history with the base."

    public init() {}

    public func load(base: String, catalog: RefCatalog, includeRemotes: Bool = false, using git: GitReadOnly) async throws -> BranchMapSnapshot {
        let baseSHA = try await git.resolve(base)
        let seeds = await Self.seeds(catalog, includeRemotes: includeRemotes, git: git)
        let entries = await BoundedConcurrency.map(seeds, limit: Self.concurrency) { seed in
            let metrics = await self.metrics(base: baseSHA, tip: seed.sha, git: git)
            return BranchMapEntry(ref: seed.ref, name: seed.name, sha: seed.sha, kind: seed.kind, worktree: seed.worktree, metrics: metrics)
        }
        try Task.checkCancellation()
        return BranchMapSnapshot(base: base, baseSHA: baseSHA, entries: BranchMapLayout.sorted(entries, by: .closest))
    }

    func metrics(base: String, tip: String, git: GitReadOnly) async -> BranchMapMetrics {
        let key = Key(base: base, tip: tip)
        if let value = cache[key] { cacheHits += 1; return value }
        if let task = pending[key] { return await task.value }
        computations += 1
        let task = Task { await Self.readMetrics(base: base, tip: tip, git: git) }
        pending[key] = task
        let value = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        pending[key] = nil
        if !Task.isCancelled, value.problem == nil || value.problem == Self.unrelated { cache[key] = value }
        return value
    }

    private static func readMetrics(base: String, tip: String, git: GitReadOnly) async -> BranchMapMetrics {
        do {
            try Task.checkCancellation()
            let reader = BranchGit(git: git)
            let tipCommit = try await reader.commit(tip)
            let counts = try await reader.counts(base, tip)
            guard let mergeBase = try await reader.mergeBase(base, tip) else {
                return BranchMapMetrics(ahead: counts.ahead, behind: counts.behind, fork: nil, tip: tipCommit, problem: unrelated)
            }
            let fork = try await reader.commit(mergeBase)
            let commits = try await reader.commits(base + ".." + tip, maximum: dotLimit, flags: ["--reverse", "--topo-order"])
            return BranchMapMetrics(ahead: counts.ahead, behind: counts.behind, fork: fork, tip: tipCommit, commits: commits)
        } catch { return BranchMapMetrics(ahead: nil, behind: nil, fork: nil, tip: nil, problem: String(describing: error)) }
    }

    private struct Seed: Sendable {
        let ref: String; let name: String; let sha: String; let kind: BranchMapEntry.Kind; let worktree: String?
    }

    private static func seeds(_ catalog: RefCatalog, includeRemotes: Bool, git: GitReadOnly) async -> [Seed] {
        var seeds: [Seed] = []
        let symbolic: Set<String>
        if includeRemotes, let listing = try? await git.string(["for-each-ref", "--format=%(refname)%00%(symref)", "refs/remotes"]) {
            symbolic = Set(listing.split(separator: "\n").compactMap { line in
                let fields = line.split(separator: "\0", omittingEmptySubsequences: false)
                return fields.count == 2 && !fields[1].isEmpty ? String(fields[0]) : nil
            })
        } else { symbolic = [] }
        for ref in catalog.refs where ref.kind == .local || (includeRemotes && ref.kind == .remote) {
            if symbolic.contains(ref.fullName) { continue }
            let worktree = catalog.worktrees.first { $0.branch == ref.name && ref.kind == .local }
            seeds.append(Seed(ref: ref.fullName, name: ref.name, sha: ref.sha,
                              kind: worktree.map(kind) ?? (ref.kind == .remote ? .remote : .branch), worktree: worktree?.path))
        }
        let names = Set(seeds.map(\.ref))
        for worktree in catalog.worktrees where !worktree.isBare {
            guard let sha = worktree.head else { continue }
            let ref = worktree.branch.map { "refs/heads/" + $0 } ?? "worktree:" + worktree.path
            guard !names.contains(ref) else { continue }
            seeds.append(Seed(ref: ref, name: worktree.branch ?? "Detached · " + worktree.url.lastPathComponent,
                              sha: sha, kind: kind(worktree), worktree: worktree.path))
        }
        return seeds
    }

    private static func kind(_ worktree: Worktree) -> BranchMapEntry.Kind {
        if worktree.kind == .claude { return .claude }
        if worktree.kind == .cursor || worktree.path.contains("/.cursor/worktrees/") { return .cursor }
        return .worktree
    }
}
