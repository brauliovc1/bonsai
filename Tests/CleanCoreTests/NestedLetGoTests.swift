@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// P12b review round 3: inside a repo the check lets go of, what that repo tracks is its content (committed bare-repo
/// fixtures, libgit2-style), and a clean clone's own submodules go through the clone rules by their git dir.
/// Cases run one at a time: each builds real repos, and together they load the machine past what the timing tests
/// (ProcessRunner, lock timeouts) tolerate.
@Suite("Nested repos: what a let-go repo holds", .serialized)
struct NestedLetGoTests {
    /// libgit2-style test fixtures: a bare repo committed as plain files (HEAD, config, objects/, refs/).
    static let bareFixture = [
        "Tests/Fixtures/testrepo.git/HEAD": "ref: refs/heads/master\n",
        "Tests/Fixtures/testrepo.git/config": "[core]\n\tbare = true\n",
        "Tests/Fixtures/testrepo.git/objects/info/packs": "\n",
        "Tests/Fixtures/testrepo.git/refs/heads/master": "0123456789012345678901234567890123456789\n",
    ]

    /// A pushed remote seeded with `files` (and `extra`, a git command run in the seed first), tagged 1.0.0.
    static func remote(_ fixture: GitFixture, _ name: String, files: [String: String], extra: [String] = []) async throws -> URL {
        let id = UUID().uuidString.prefix(8)
        let remote = fixture.remotes.appending(path: "\(name)-\(id).git")
        try await fixture.run(["init", "--quiet", "--bare", remote.path], in: fixture.url)
        let seed = fixture.url.appending(path: "seed-\(name)-\(id)")
        try await fixture.run(["clone", "--quiet", remote.path, seed.path], in: fixture.url)
        for (path, text) in files { try fixture.write(text, to: path, in: seed) }
        if !extra.isEmpty { try await fixture.run(["-c", "protocol.file.allow=always"] + extra, in: seed) }
        try await fixture.commitAll(in: seed, message: "Release")
        try await fixture.run(["tag", "1.0.0"], in: seed)
        try await fixture.run(["push", "--quiet", "origin", "main", "--tags"], in: seed)
        return remote
    }

    /// A clone of `remote` at `target`, detached at 1.0.0, with its submodules when `recurse`.
    @discardableResult
    static func clone(_ fixture: GitFixture, _ remote: URL, to target: URL, recurse: Bool = false) async throws -> URL {
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await fixture.run(["-c", "protocol.file.allow=always", "clone", "--quiet"] + (recurse ? ["--recurse-submodules"] : [])
            + [remote.path, target.path], in: fixture.url)
        try await fixture.run(["checkout", "--quiet", "--detach", "1.0.0"], in: target)
        return target
    }

    @Test(arguments: [".build/checkouts/gitlib", "node_modules/gitlib"])
    func committedBareFixturesInsideALetGoRepoDontBlock(_ at: String) async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("pkg")
        let lib = try await Self.remote(world.fixture, "gitlib", files: Self.bareFixture.merging(["Package.swift": "// x\n"]) { a, _ in a })
        try await Self.clone(world.fixture, lib, to: wt.appending(path: at, directoryHint: .isDirectory))
        let report = try await world.check(wt)
        #expect(report.blockers.isEmpty, "\(at): \(report)")
    }

    /// When git can't list what the copy tracks (here: no index), its bare-shaped folder keeps the rule: blocking is
    /// the safe side.
    @Test func withoutTheCopysListingTheFixtureKeepsTheRule() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("pkg")
        let lib = try await Self.remote(world.fixture, "gitlib", files: Self.bareFixture)
        let copy = try await Self.clone(world.fixture, lib, to: wt.appending(path: ".build/checkouts/gitlib", directoryHint: .isDirectory))
        try FileManager.default.removeItem(at: copy.appending(path: ".git/index"))
        let report = try await world.check(wt)
        #expect(report.blockers == [.nestedCheckouts([".build/checkouts/gitlib/Tests/Fixtures/testrepo.git"])], "\(report)")
    }

    /// A real bare repo the clean clone doesn't track (in its ignored node_modules) still blocks.
    @Test func anUntrackedBareRepoInsideACleanCloneBlocks() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("npm")
        let lib = try await PackageCopyInsideTests.cleanCloneIgnoringNodeModules(world.fixture, in: wt, at: "node_modules/lib")
        let bare = lib.appending(path: "node_modules/backup.git")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        try await world.fixture.run(["init", "--quiet", "--bare", bare.path], in: world.fixture.url)
        let report = try await world.check(wt)
        #expect(report.blockers == [.nestedCheckouts(["node_modules/lib/node_modules/backup.git"])], "\(report)")
    }

    enum Submodule: String, CaseIterable {
        /// A commit on a branch `mine`, HEAD back at the recorded commit: only in the clone's `.git/modules/sub`.
        case branchOnlyCommit
        /// Nothing local.
        case clean
    }

    /// A clean clone's own submodule goes through the clone rules by its git dir.
    @Test(arguments: Submodule.allCases)
    func aCleanClonesSubmoduleIsChecked(_ state: Submodule) async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("npm")
        let fixture = world.fixture
        let sub = try await Self.remote(fixture, "sub", files: ["sub.txt": "sub\n"])
        let lib = try await Self.remote(fixture, "lib", files: ["index.js": "1\n"], extra: ["submodule", "add", "--quiet", sub.path, "sub"])
        let clone = try await Self.clone(fixture, lib, to: wt.appending(path: "node_modules/lib", directoryHint: .isDirectory), recurse: true)
        if state == .branchOnlyCommit {
            let subDir = clone.appending(path: "sub", directoryHint: .isDirectory)
            let recorded = try await fixture.run(["rev-parse", "HEAD"], in: subDir)
            try await fixture.run(["checkout", "--quiet", "-b", "mine"], in: subDir)
            try fixture.write("only here\n", to: "mine.txt", in: subDir)
            try await fixture.commitAll(in: subDir, message: "Mine")
            try await fixture.run(["checkout", "--quiet", "--detach", recorded], in: subDir)
        }
        #expect(try await fixture.run(["status", "--porcelain"], in: clone).isEmpty, "the clone itself looks clean")

        let found = await SafetyCheck(git: fixture.git).state(of: try await world.worktree(wt))
        switch state {
        case .branchOnlyCommit:
            #expect(found.nestedLocalWork.map(\.path) == ["node_modules/lib/sub"], "\(found)")
            #expect(found.nestedLocalWork.first?.findings.contains("1 commit not on a remote") == true)
            #expect(!(try await world.check(wt)).manualAllowed)
        case .clean:
            #expect(found.nestedClones == ["node_modules/lib", "node_modules/lib/sub"], "\(found)")
            #expect(found.nestedCheckouts.isEmpty)
            #expect((try await world.check(wt)).blockers.isEmpty)
        }
    }

    /// A package copy's own submodule stays build output (§4.1), whatever it holds.
    @Test func aCopysSubmoduleStaysBuildOutput() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("swiftpm")
        let fixture = world.fixture
        let sub = try await Self.remote(fixture, "sub", files: ["sub.txt": "sub\n"])
        let lib = try await Self.remote(fixture, "lib", files: ["Package.swift": "// x\n"], extra: ["submodule", "add", "--quiet", sub.path, "sub"])
        let copy = try await Self.clone(fixture, lib, to: wt.appending(path: ".build/checkouts/lib", directoryHint: .isDirectory), recurse: true)
        let subDir = copy.appending(path: "sub", directoryHint: .isDirectory)
        try await fixture.run(["checkout", "--quiet", "-b", "mine"], in: subDir)
        try fixture.write("x\n", to: "mine.txt", in: subDir)
        try await fixture.commitAll(in: subDir, message: "Mine")
        let report = try await world.check(wt)
        #expect(report.blockers.isEmpty, "\(report)")
        #expect(report.notes.contains(.packageCopies([".build/checkouts/lib"])))
    }
}
