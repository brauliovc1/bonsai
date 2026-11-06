import Foundation

/// Puts a removed worktree back with `git worktree add` from the kept branch (or commit, when it was
/// detached). Dependencies are not reinstalled.
public struct Restorer: Sendable {
    public var git: Git
    public var log: RemovalLog
    public var now: @Sendable () -> Date

    public init(git: Git, environment: CleanEnvironment) {
        self.git = git
        self.log = RemovalLog(environment: environment)
        self.now = environment.now
    }

    public static let dependenciesNote = "Dependencies were not reinstalled; run your package manager in the folder if it needs them."

    /// What `restore` would run, once every precondition holds.
    public struct Plan: Sendable, Hashable {
        public var entry: RemovalLogEntry
        /// Arguments after `git -C <repo>`.
        public var arguments: [String]
    }

    public struct Result: Sendable, Hashable {
        public var entry: RemovalLogEntry
        public var path: String
        /// The branch, or the commit for a detached worktree.
        public var ref: String
        public var warnings: [String]
        public var note: String { Restorer.dependenciesNote }
    }

    public enum RestoreError: Error, Sendable, Equatable, CustomStringConvertible {
        case notFound(String)
        case notAWorktreeRemoval(RemovalAction)
        case alreadyRestored(Date)
        case pathExists(String)
        case repoMissing(String)
        case branchMissing(String)
        case commitMissing(String)
        case noRef
        case gitFailed(String)

        public var description: String {
            switch self {
            case .notFound(let id): "no log entry matches \(id)"
            case .notAWorktreeRemoval(let action): "only removed worktrees can be restored (this entry is \(action.rawValue))"
            case .alreadyRestored(let date): "already restored on \(date.formatted(.iso8601))"
            case .pathExists(let path): "\(path) already exists; move it away first"
            case .repoMissing(let path): "the repo \(path) no longer exists"
            case .branchMissing(let branch): "branch \(branch) no longer exists"
            case .commitMissing(let sha): "commit \(sha) no longer exists in the repo"
            case .noRef: "the log entry has neither a branch nor a commit"
            case .gitFailed(let stderr): "git refused: " + stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    /// Checks every precondition without changing anything.
    public func plan(entryID: UUID) async throws -> Plan {
        guard let entry = try log.entry(id: entryID) else { throw RestoreError.notFound(entryID.uuidString) }
        guard entry.action == .worktreeRemove else { throw RestoreError.notAWorktreeRemoval(entry.action) }
        if let restoredAt = entry.restoredAt { throw RestoreError.alreadyRestored(restoredAt) }
        guard !Remover.itemExists(at: entry.path) else { throw RestoreError.pathExists(entry.path) }

        let repo = URL(fileURLWithPath: entry.repoPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: repo.path, isDirectory: &isDirectory), isDirectory.boolValue
        else { throw RestoreError.repoMissing(entry.repoPath) }

        if let branch = entry.branch {
            let check = try await git.result(["rev-parse", "--verify", "--quiet", "refs/heads/\(branch)"], in: repo)
            guard check.succeeded else { throw RestoreError.branchMissing(branch) }
            return Plan(entry: entry, arguments: Git.unicodeOptions(forPath: entry.path) + ["worktree", "add", entry.path, branch])
        }
        guard let sha = entry.headSha else { throw RestoreError.noRef }
        let check = try await git.result(["cat-file", "-e", "\(sha)^{commit}"], in: repo)
        guard check.succeeded else { throw RestoreError.commitMissing(sha) }
        return Plan(entry: entry, arguments: Git.unicodeOptions(forPath: entry.path) + ["worktree", "add", "--detach", entry.path, sha])
    }

    public func restore(entryID: UUID) async throws -> Result {
        let plan = try await plan(entryID: entryID)
        let entry = plan.entry
        do {
            try await git.git(plan.arguments, in: URL(fileURLWithPath: entry.repoPath, isDirectory: true))
        } catch let error as GitError {
            throw RestoreError.gitFailed(error.timedOut ? "git timed out" : error.stderr)
        }
        var warnings: [String] = []
        do {
            try log.markRestored(id: entry.id, at: now())
        } catch {
            warnings.append("restored, but the log could not be updated: \(error)")
        }
        return Result(entry: entry, path: entry.path, ref: entry.branch ?? entry.headSha ?? "", warnings: warnings)
    }
}
