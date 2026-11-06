import Foundation

/// `git worktree prune` for worktrees whose folders are gone. git only touches registrations whose
/// folder no longer exists (and never locked ones); nothing on disk outside `.git/worktrees` changes.
public struct Pruner: Sendable {
    public var git: Git
    public var log: RemovalLog
    public var now: @Sendable () -> Date

    public init(git: Git, environment: CleanEnvironment) {
        self.git = git
        self.log = RemovalLog(environment: environment)
        self.now = environment.now
    }

    public struct Result: Sendable, Hashable {
        public var repoPath: String
        /// `worktrees/<name>: <reason>` per pruned registration.
        public var pruned: [String]
        /// nil when nothing was pruned (nothing is logged then).
        public var entry: RemovalLogEntry?
        public var warnings: [String]
    }

    /// What `prune` would remove: `git worktree prune --dry-run --verbose`.
    public func preview(repo: URL) async throws -> [String] {
        try await run(["worktree", "prune", "--dry-run", "--verbose"], in: repo)
    }

    /// Prunes, then logs one `worktreePrune` entry for the repo with the pruned names in `notes`.
    public func prune(repo: URL, mode: RemovalMode = .manual) async throws -> Result {
        let pruned = try await run(["worktree", "prune", "--verbose"], in: repo)
        guard !pruned.isEmpty else { return Result(repoPath: repo.path, pruned: [], entry: nil, warnings: []) }
        let entry = RemovalLogEntry(
            date: now(),
            mode: mode,
            action: .worktreePrune,
            repoPath: repo.path,
            path: repo.path,
            notes: pruned
        )
        var warnings: [String] = []
        do {
            try log.append(entry)
        } catch {
            warnings.append("the prune was not logged: \(error)")
        }
        return Result(repoPath: repo.path, pruned: pruned, entry: entry, warnings: warnings)
    }

    /// git prints `Removing worktrees/<name>: <reason>` on stderr.
    private func run(_ arguments: [String], in repo: URL) async throws -> [String] {
        let result = try await git.result(arguments, in: repo)
        guard result.succeeded else {
            throw GitError(exitCode: result.exitCode, stderr: result.stderr, arguments: arguments, timedOut: result.timedOut)
        }
        return Self.parse(result.stderr + "\n" + result.stdoutString)
    }

    static func parse(_ output: String) -> [String] {
        let prefix = "Removing "
        return output.split(separator: "\n").compactMap { line in
            line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : nil
        }
    }
}
