import CleanCore
import Foundation

/// A throwaway world of real git repos in a temp folder:
///
/// ```
/// <tmp>/bonsai-fixture-<uuid>/
///   home/       HOME for git and for `environment()` (.claude, .cursor/worktrees, Library/...)
///   remotes/    one bare remote per repo
///   root/       the scan root; main clones go here by default
/// ```
///
/// Every git call runs with `HOME=<home>`, `GIT_CONFIG_NOSYSTEM=1` and fixed `-c` settings, so the user's
/// global git config, hooks and commit signing never apply. Call `remove()` when done (also on deinit).
///
/// git is the real binary (`TestTools`), and `git` and `environment()` give the code under test `TestWait.limit`
/// for every git and lsof call: on a crowded machine a slow answer stays an answer. The fixture's own git calls
/// (`run`, `makeRepo`…) wait for a slot in `ProcessLimit.helpers`.
public final class GitFixture: Sendable {
    public struct FixtureError: Error, CustomStringConvertible {
        public var description: String
    }

    public let directory: TemporaryDirectory
    public let home: URL
    public let remotes: URL
    public let scanRoot: URL
    public let git: Git

    /// What `environment()` gives the code under test.
    public static let timeouts = ToolTimeouts(git: TestWait.limit, gitVersion: TestWait.limit, lsof: TestWait.limit)

    public convenience init() throws {
        try self.init(directory: TemporaryDirectory(prefix: "bonsai-fixture"))
    }

    /// A fixture in `folder` (inside the temp dir), left in place when the fixture goes away.
    public convenience init(keeping folder: URL) throws {
        try self.init(directory: TemporaryDirectory(keeping: folder))
    }

    init(directory: TemporaryDirectory) throws {
        guard let executable = TestTools.paths.git else { throw FixtureError(description: "git not found") }
        self.directory = directory
        home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        remotes = directory.url.appending(path: "remotes", directoryHint: .isDirectory)
        scanRoot = directory.url.appending(path: "root", directoryHint: .isDirectory)
        for folder in [home, remotes, scanRoot] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        git = Git(
            executable: executable,
            environmentAdditions: [
                "HOME": home.path,
                "XDG_CONFIG_HOME": home.appending(path: ".config").path,
                "GIT_CONFIG_NOSYSTEM": "1",
            ],
            leadingArguments: [
                "-c", "user.name=Fixture",
                "-c", "user.email=fixture@example.invalid",
                "-c", "commit.gpgsign=false",
                "-c", "init.defaultBranch=main",
            ],
            timeout: Self.timeouts.git
        )
    }

    /// The fixture folder itself.
    public var url: URL { directory.url }

    public func remove() {
        directory.remove()
    }

    /// A `CleanEnvironment` whose home, Claude dirs, Cursor dir and settings dir all live in `home`.
    public func environment(scanRoots: [URL]? = nil) -> CleanEnvironment {
        var environment = CleanEnvironment.make(homeDirectory: home, variables: [:], tools: TestTools.paths)
        environment.scanRootsOverride = scanRoots
        environment.timeouts = Self.timeouts
        return environment
    }

    /// Runs git with the fixture's isolation settings, plus `environment` (author and committer dates, say).
    @discardableResult
    public func run(_ args: [String], in directory: URL, adding environment: [String: String] = [:]) async throws -> String {
        var git = self.git
        git.environmentAdditions.merge(environment) { _, added in added }
        return try await ProcessLimit.helpers.run { [git] in try await git.gitString(args, in: directory) }
    }

    /// A bare remote plus a main clone at `<parent>/<name>` with one commit pushed to `origin/main`.
    @discardableResult
    public func makeRepo(_ name: String, in parent: URL? = nil) async throws -> URL {
        let clone = (parent ?? scanRoot).appending(path: name, directoryHint: .isDirectory)
        let remote = remotes.appending(path: "\(name)-\(UUID().uuidString.prefix(8)).git")
        try FileManager.default.createDirectory(at: clone.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await run(["init", "--quiet", "--bare", remote.path], in: url)
        try await run(["clone", "--quiet", remote.path, clone.path], in: url)
        try Data("# \(name)\n".utf8).write(to: clone.appending(path: "README.md"))
        try await run(["add", "README.md"], in: clone)
        try await run(["commit", "--quiet", "-m", "Initial commit"], in: clone)
        try await run(["push", "--quiet", "-u", "origin", "main"], in: clone)
        return clone
    }

    /// `git worktree add` at `path`: on a new branch (default: the folder name) or detached.
    @discardableResult
    public func addWorktree(to repo: URL, at path: URL, branch: String? = nil, detached: Bool = false) async throws -> URL {
        let target = detached ? ["--detach"] : ["-b", branch ?? path.lastPathComponent]
        try await run(["worktree", "add", "--quiet"] + target + [path.path], in: repo)
        return path
    }

    /// A sibling worktree: `<parent of repo>/<repo>-<name>`.
    @discardableResult
    public func addSiblingWorktree(to repo: URL, name: String, branch: String? = nil) async throws -> URL {
        let path = repo.deletingLastPathComponent()
            .appending(path: "\(repo.lastPathComponent)-\(name)", directoryHint: .isDirectory)
        return try await addWorktree(to: repo, at: path, branch: branch ?? name)
    }

    /// A Claude-app worktree: `<repo>/.claude/worktrees/<name>` on branch `claude/<name>`.
    @discardableResult
    public func addClaudeWorktree(to repo: URL, name: String) async throws -> URL {
        let path = repo.appending(path: ".claude/worktrees/\(name)", directoryHint: .isDirectory)
        return try await addWorktree(to: repo, at: path, branch: "claude/\(name)")
    }

    /// A Cursor worktree: `<home>/.cursor/worktrees/<repo>/<name>`, detached like Cursor's.
    @discardableResult
    public func addCursorWorktree(to repo: URL, name: String) async throws -> URL {
        let path = environment().cursorWorktreesDirectory
            .appending(path: "\(repo.lastPathComponent)/\(name)", directoryHint: .isDirectory)
        return try await addWorktree(to: repo, at: path, detached: true)
    }

    public func lock(_ worktree: URL, in repo: URL, reason: String? = nil) async throws {
        let reasonArgs = reason.map { ["--reason", $0] } ?? []
        try await run(["worktree", "lock"] + reasonArgs + [worktree.path], in: repo)
    }

    /// Detaches HEAD in a worktree (keeps the branch).
    public func detach(_ worktree: URL) async throws {
        try await run(["checkout", "--quiet", "--detach"], in: worktree)
    }

    /// Deletes a worktree's folder behind git's back, so git reports it as prunable.
    public func deleteFolder(_ worktree: URL) throws {
        try removeInsideFixture(worktree)
    }

    /// Overwrites `.git/HEAD` with garbage, so every git command in the repo fails.
    public func corruptHead(of repo: URL) throws {
        try Data("this is not a ref\n".utf8).write(to: repo.appending(path: ".git/HEAD"))
    }

    private func removeInsideFixture(_ target: URL) throws {
        guard CanonicalPath.isInside(target, directory: url), TemporaryDirectory.isDisposable(target) else {
            throw FixtureError(description: "refusing to delete \(target.path): not inside the fixture")
        }
        try FileManager.default.removeItem(at: target)
    }
}
