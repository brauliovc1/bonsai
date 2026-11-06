import Foundation

/// Lists the worktrees of each repo with `git worktree list --porcelain -z`.
public struct WorktreeScanner: Sendable {
    public var git: Git
    public var cursorWorktreesDirectory: URL
    public var maxConcurrentRepos: Int

    public init(git: Git, cursorWorktreesDirectory: URL, maxConcurrentRepos: Int = 4) {
        self.git = git
        self.cursorWorktreesDirectory = cursorWorktreesDirectory
        self.maxConcurrentRepos = maxConcurrentRepos
    }

    public struct Listing: Sendable {
        public var worktrees: [Worktree]
        public var issues: [ScanIssue]
    }

    /// Lists every repo, at most `maxConcurrentRepos` at a time. A repo whose listing fails becomes an
    /// issue; the other repos are still listed. Worktrees keep the order of `repos`.
    public func scan(
        repos: [URL],
        onRepoFinished: @Sendable (_ completed: Int, _ total: Int) -> Void = { _, _ in }
    ) async -> Listing {
        let total = repos.count
        let outcomes = await BoundedConcurrency.map(
            repos,
            limit: maxConcurrentRepos,
            onCompletion: { onRepoFinished($0, total) }
        ) { repo -> Result<[Worktree], GitError> in
            do {
                return .success(try await worktrees(in: repo))
            } catch let error as GitError {
                return .failure(error)
            } catch {
                return .failure(GitError(exitCode: -1, stderr: "\(error)", arguments: Self.listArguments))
            }
        }

        var listing = Listing(worktrees: [], issues: [])
        for (repo, outcome) in zip(repos, outcomes) {
            switch outcome {
            case .success(let worktrees):
                listing.worktrees += worktrees
            case .failure(let error):
                listing.issues.append(ScanIssue(kind: .worktreeListFailed, path: repo.path, message: error.description))
            }
        }
        return listing
    }

    static let listArguments = ["worktree", "list", "--porcelain", "-z"]

    /// The worktrees of one repo: main checkout first, then linked worktrees sorted by path.
    public func worktrees(in repo: URL) async throws -> [Worktree] {
        let output = try await git.git(Self.listArguments, in: repo)
        let records = WorktreeListParser.parse(output)
        guard let mainRecord = records.first else { return [] }
        let mainPath = URL(fileURLWithPath: mainRecord.path)

        let worktrees = records.enumerated().map { index, record in
            let isMain = index == 0
            return Worktree(
                path: record.path,
                repoPath: repo.path,
                head: record.head,
                branch: record.isDetached ? nil : record.branch,
                isMain: isMain,
                isBare: record.isBare,
                lockedReason: record.lockedReason,
                prunableReason: record.prunableReason,
                kind: WorktreeKind.classify(
                    path: URL(fileURLWithPath: record.path),
                    isMain: isMain,
                    mainPath: mainPath,
                    cursorWorktreesDirectory: cursorWorktreesDirectory
                )
            )
        }
        return [worktrees[0]] + worktrees.dropFirst().sorted { $0.path < $1.path }
    }
}
