import Foundation

/// Finds the folders light clean may delete in one worktree or main checkout (PLAN §4.2). Read-only.
///
/// A folder is a candidate only when its name is in `RegenerableNames.folders`, git tracks nothing in it,
/// `git check-ignore` says it is ignored, the worktree's `git status` lists nothing in it, it is not a
/// symlink, and no other checkout with local work is inside it (§4.1 nested checkouts). The walk goes to
/// depth 4 and never into `.git` or a folder that matched.
public struct LightCleanFinder: Sendable {
    public var git: Git
    /// For size estimates; nil = no estimates.
    public var du: URL?
    public var nestedSearch: NestedCheckoutSearch
    /// Folders checked at the same time.
    public var maxConcurrent: Int

    public init(git: Git, du: URL?, nestedSearch: NestedCheckoutSearch = NestedCheckoutSearch(), maxConcurrent: Int = 4) {
        self.git = git
        self.du = du
        self.nestedSearch = nestedSearch
        self.maxConcurrent = maxConcurrent
    }

    /// `knownWorktrees`: every registered worktree of every scanned repo; one inside a folder keeps it.
    public func candidates(
        in worktree: Worktree,
        knownWorktrees: [Worktree] = [],
        measureSizes: Bool = true
    ) async -> LightCleanFindings {
        if worktree.isBare { return LightCleanFindings(worktree: worktree, problem: "a bare repo has no working folder") }
        if worktree.isPrunable || DirectoryEntries.kind(ofItemAt: worktree.path) != .directory {
            return LightCleanFindings(worktree: worktree, problem: "the folder is missing")
        }

        let walk = LightCleanWalk().walk(worktree.path)
        let check = LightCleanCheck(git: git, nestedSearch: nestedSearch)
        let root = worktree.url
        let status: LightCleanStatus
        do {
            status = walk.matches.isEmpty ? LightCleanStatus(paths: []) : try await LightCleanStatus.read(git: git, worktree: root)
        } catch {
            let skipped = walk.matches.map {
                LightCleanSkip(relativePath: $0.relativePath, name: $0.name, reason: .gitError("git status failed: \(error)"))
            }
            return LightCleanFindings(worktree: worktree, skipped: skipped, unreadable: walk.unreadable)
        }
        let verdicts = await BoundedConcurrency.map(walk.matches, limit: maxConcurrent) { match in
            if match.isSymlink { return LightCleanCheck.Verdict(reason: .symlink) }
            return await check.verdict(for: match.relativePath, in: root, status: status, knownWorktrees: knownWorktrees)
        }

        var passing: [(match: LightCleanWalk.Match, packageClones: [String])] = []
        var skipped: [LightCleanSkip] = []
        for (match, verdict) in zip(walk.matches, verdicts) {
            if let reason = verdict.reason {
                skipped.append(LightCleanSkip(relativePath: match.relativePath, name: match.name, reason: reason))
            } else {
                passing.append((match, verdict.packageClones))
            }
        }

        var sizes: [String: Int64] = [:]
        let urls = passing.map { root.appending(path: $0.match.relativePath, directoryHint: .isDirectory) }
        if measureSizes, let du, !urls.isEmpty {
            sizes = await DirectorySizer(du: du).sizes(of: urls).sizes
        }
        let candidates = zip(passing, urls).map { item, url in
            LightCleanCandidate(
                worktreePath: worktree.path,
                relativePath: item.match.relativePath,
                name: item.match.name,
                estimatedBytes: sizes[url.path],
                packageClones: item.packageClones
            )
        }
        return LightCleanFindings(worktree: worktree, candidates: candidates, skipped: skipped, unreadable: walk.unreadable)
    }
}
