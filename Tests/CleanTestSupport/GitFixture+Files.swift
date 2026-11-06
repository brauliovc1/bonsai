import CleanCore
import Foundation

extension GitFixture {
    /// Writes `text` to `relativePath` inside `folder`, creating parent folders.
    @discardableResult
    public func write(_ text: String, to relativePath: String, in folder: URL) throws -> URL {
        let file = folder.appending(path: relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
        return file
    }

    /// `git add -A && git commit` in `folder`.
    public func commitAll(in folder: URL, message: String = "Change") async throws {
        try await run(["add", "-A"], in: folder)
        try await run(["commit", "--quiet", "-m", message], in: folder)
    }

    /// The worktree record git lists for `path` in `repo`.
    public func worktree(at path: URL, in repo: URL) async throws -> Worktree {
        let scanner = WorktreeScanner(git: git, cursorWorktreesDirectory: environment().cursorWorktreesDirectory)
        guard let worktree = try await scanner.worktrees(in: repo).first(where: { CanonicalPath.same($0.url, path) })
        else { throw FixtureError(description: "\(path.path) is not a worktree of \(repo.path)") }
        return worktree
    }

    /// A repo with one commit and no remote at all.
    @discardableResult
    public func makeLocalOnlyRepo(_ name: String) async throws -> URL {
        let repo = scanRoot.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try await run(["init", "--quiet"], in: repo)
        try write("# \(name)\n", to: "README.md", in: repo)
        try await commitAll(in: repo, message: "Initial commit")
        return repo
    }

    /// Sets the modification date of `url`, or of every file and folder under it (not following symlinks).
    public func setModificationDate(_ date: Date, of url: URL, recursively: Bool = false) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        guard recursively else { return }
        guard let enumerator = FileManager.default.enumerator(atPath: url.path) else { return }
        while let relative = enumerator.nextObject() as? String {
            try FileManager.default.setAttributes(
                [.modificationDate: date],
                ofItemAtPath: url.appending(path: relative).path
            )
        }
    }

    /// A settings folder inside the fixture, and an environment whose clock is `offset` seconds ahead.
    public func environment(clockOffset offset: TimeInterval) -> CleanEnvironment {
        var environment = environment()
        environment.now = { Date().addingTimeInterval(offset) }
        return environment
    }
}
