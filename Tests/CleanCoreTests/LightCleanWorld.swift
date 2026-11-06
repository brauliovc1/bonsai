@testable import CleanCore
import CleanTestSupport
import Foundation

/// A fixture repo for light clean: `.gitignore` ignores `node_modules/`, `.build/` and
/// `/.claude/worktrees/` (not `build` or `dist`), and is pushed to `origin/main`.
struct LightCleanWorld {
    let fixture: GitFixture
    let repo: URL

    static let gitignore = "node_modules/\n.build/\n/.claude/worktrees/\n"

    static func make(_ name: String = "app") async throws -> LightCleanWorld {
        let fixture = try GitFixture()
        let repo = try await fixture.makeRepo(name)
        try fixture.write(gitignore, to: ".gitignore", in: repo)
        try await fixture.commitAll(in: repo, message: "Ignore dependencies")
        try await fixture.run(["push", "--quiet", "origin", "main"], in: repo)
        return LightCleanWorld(fixture: fixture, repo: repo)
    }

    func remove() {
        fixture.remove()
    }

    func worktree(_ path: URL, in repo: URL? = nil) async throws -> Worktree {
        try await fixture.worktree(at: path, in: repo ?? self.repo)
    }

    /// Every worktree of the world's repo.
    func known(_ repos: [URL]? = nil) async throws -> [Worktree] {
        let scanner = WorktreeScanner(git: fixture.git, cursorWorktreesDirectory: fixture.environment().cursorWorktreesDirectory)
        var all: [Worktree] = []
        for repo in repos ?? [self.repo] { all += try await scanner.worktrees(in: repo) }
        return all
    }

    func finder(nestedSearch: NestedCheckoutSearch = NestedCheckoutSearch()) -> LightCleanFinder {
        LightCleanFinder(git: fixture.git, du: fixture.environment().tools.du, nestedSearch: nestedSearch)
    }

    /// A cleaner logging into the fixture's settings folder. `cwdIndex` replaces lsof (nil = real lsof).
    func cleaner(cwdIndex: ProcessCwdIndex? = ProcessCwdIndex(entries: []), freeSpace: [Int64?]? = nil) -> LightCleaner {
        var cleaner = LightCleaner(git: fixture.git, environment: fixture.environment())
        if let cwdIndex { cleaner.captureCwdIndex = { cwdIndex } }
        if let freeSpace { cleaner.freeSpace = ScriptedFreeSpace(freeSpace).probe }
        return cleaner
    }

    var log: RemovalLog {
        RemovalLog(environment: fixture.environment())
    }

    /// A file of `kibibytes` KiB at `relative` inside `folder` (parents created).
    @discardableResult
    func file(_ relative: String, in folder: URL, kibibytes: Int = 4) throws -> URL {
        let file = folder.appending(path: relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: kibibytes * 1024).write(to: file)
        return file
    }

    /// A clone the way a package manager leaves it: from a bare remote into `<folder>/<relative>`, detached
    /// at a pushed tag, with no local work.
    @discardableResult
    func packageClone(in folder: URL, at relative: String) async throws -> URL {
        let id = UUID().uuidString.prefix(8)
        let remote = fixture.remotes.appending(path: "pkg-\(id).git")
        try await fixture.run(["init", "--quiet", "--bare", remote.path], in: fixture.url)
        let seed = fixture.url.appending(path: "seed-\(id)")
        try await fixture.run(["clone", "--quiet", remote.path, seed.path], in: fixture.url)
        try fixture.write("// package\n", to: "Package.swift", in: seed)
        try await fixture.commitAll(in: seed, message: "Release")
        try await fixture.run(["tag", "1.0.0"], in: seed)
        try await fixture.run(["push", "--quiet", "origin", "main", "--tags"], in: seed)

        let clone = folder.appending(path: relative)
        try FileManager.default.createDirectory(at: clone.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await fixture.run(["clone", "--quiet", remote.path, clone.path], in: fixture.url)
        try await fixture.run(["checkout", "--quiet", "--detach", "1.0.0"], in: clone)
        return clone
    }

    func exists(_ relative: String, in folder: URL) -> Bool {
        Remover.itemExists(at: folder.appending(path: relative).path)
    }
}
