import Foundation

/// What the Worktrees screen shows about a worktree's history: last commit, remotes, recent commits,
/// upstream. Read-only, through `Git` (fsmonitor off, no optional locks, inherited `GIT_*` stripped).
///
/// Every command runs in the main repo folder and names a commit by the hash git's worktree record holds,
/// or a branch by its ref: no path is ever passed to git (P2: `Process` decomposes non-ASCII arguments),
/// a missing folder still has a last commit, and a stale record's folder is never read.
public struct GitInfoReader: Sendable {
    public var git: Git
    /// git processes at the same time (the scan's concurrency).
    public var maxConcurrent: Int

    public init(git: Git, maxConcurrent: Int = 4) {
        self.git = git
        self.maxConcurrent = maxConcurrent
    }

    /// The commit each worktree's HEAD points at, by worktree path: one `git log -1` per distinct commit.
    /// Bare entries and failures are left out.
    public func lastCommits(of worktrees: [Worktree]) async -> [String: CommitSummary] {
        struct Key: Hashable, Sendable {
            var repo: String
            var sha: String
        }
        let keys = worktrees.compactMap { worktree in worktree.head.map { Key(repo: worktree.repoPath, sha: $0) } }
        let unique = Array(Set(keys))
        let commits = await BoundedConcurrency.map(unique, limit: maxConcurrent) { key in
            await lastCommit(sha: key.sha, in: URL(fileURLWithPath: key.repo, isDirectory: true))
        }
        let byKey = Dictionary(uniqueKeysWithValues: zip(unique, commits))
        var result: [String: CommitSummary] = [:]
        for worktree in worktrees {
            guard let sha = worktree.head, let commit = byKey[Key(repo: worktree.repoPath, sha: sha)] ?? nil else {
                continue
            }
            result[worktree.path] = commit
        }
        return result
    }

    /// `git log -1` of one commit, run in `repo`. nil when `sha` isn't a hash or git fails.
    public func lastCommit(sha: String, in repo: URL) async -> CommitSummary? {
        guard CommitSummary.isHash(sha) else { return nil }
        let output = try? await git.git(CommitSummary.logArguments + ["-1", sha, "--"], in: repo)
        return output.flatMap { CommitSummary.parse($0).first }
    }

    /// The remotes of each repo, by repo path (`git remote -v`, once per repo). Failures are left out.
    public func remotes(of repos: [URL]) async -> [String: [GitRemote]] {
        let found = await BoundedConcurrency.map(repos, limit: maxConcurrent) { repo in
            try? await remotes(of: repo)
        }
        var result: [String: [GitRemote]] = [:]
        for (repo, remotes) in zip(repos, found) {
            if let remotes { result[Worktree.standardize(repo.path)] = remotes }
        }
        return result
    }

    /// `git remote -v` in `repo`, "origin" first, credentials stripped.
    public func remotes(of repo: URL) async throws -> [GitRemote] {
        let output = try await git.gitString(["remote", "-v"], in: repo)
        return GitRemote.preferredOrder(GitRemote.parse(output))
    }

    /// The last `count` commits reachable from the worktree's HEAD (as git's record has it), newest first.
    /// Empty for a bare entry.
    public func recentCommits(of worktree: Worktree, count: Int = 5) async throws -> [CommitSummary] {
        guard let sha = worktree.head, CommitSummary.isHash(sha) else { return [] }
        let output = try await git.git(
            CommitSummary.logArguments + ["-n", String(max(count, 1)), sha, "--"],
            in: worktree.repoURL
        )
        return CommitSummary.parse(output)
    }

    /// The upstream of the worktree's branch and how far ahead and behind it is, from the last fetch.
    /// nil when detached or the branch has no upstream.
    public func upstream(of worktree: Worktree) async throws -> UpstreamStatus? {
        guard let branch = worktree.branch, !branch.isEmpty else { return nil }
        let ref = "refs/heads/\(branch)"
        // A non-ASCII name would reach git decomposed and match nothing: list every branch and pick it here
        // (Swift compares the names by canonical equivalence). The track part costs a walk per listed branch.
        let pattern = ref.utf8.allSatisfy { $0 < 0x80 } ? ref : "refs/heads/"
        let output = try await git.gitString(
            ["for-each-ref", "--format=%(refname)%1f%(upstream:short)%1f%(upstream:track,nobracket)", pattern],
            in: worktree.repoURL
        )
        // A pattern also matches refs below it (refs/heads/a matches refs/heads/a/b): keep the exact one.
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\u{1F}", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3, fields[0] == ref else { continue }
            return UpstreamStatus.parse(upstream: String(fields[1]), track: String(fields[2]))
        }
        return nil
    }
}
