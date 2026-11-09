@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// P12b review (11-09): the search goes on inside every repo the check lets go of (package copies, clean clones, their
/// own submodules). A repo found there keeps the §4.1 rule; a `.git` file leading into the let-go repo's own
/// `.git/modules` belongs to it and is searched in turn.
/// Cases run one at a time: each builds real repos, and together they load the machine past what the timing tests
/// (ProcessRunner, lock timeouts) tolerate.
@Suite("Package copies: what's inside", .serialized)
struct PackageCopyInsideTests {
    /// A repo with local work (a commit, no remote, an uncommitted file) at `relative` inside `folder`.
    @discardableResult
    static func repoWithWork(_ fixture: GitFixture, in folder: URL, at relative: String) async throws -> URL {
        let repo = folder.appending(path: relative, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try await fixture.run(["init", "--quiet"], in: repo)
        try fixture.write("my only copy\n", to: "work.txt", in: repo)
        try await fixture.commitAll(in: repo, message: "Local only")
        try fixture.write("uncommitted\n", to: "draft.txt", in: repo)
        return repo
    }

    private func known(_ world: SafetyWorld) async throws -> [Worktree] {
        try await WorktreeScanner(git: world.fixture.git, cursorWorktreesDirectory: world.fixture.environment()
            .cursorWorktreesDirectory).worktrees(in: world.repo)
    }

    @Test func aRepoWithWorkInsideACopyBlocks() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("swiftpm")
        let (checkout, _) = try await world.fixture.xcodePackage("swift-nio", in: wt, base: ".build")
        let mine = try await Self.repoWithWork(world.fixture, in: checkout, at: "vendor/mine")

        let report = try await world.check(wt)
        #expect(report.blockers == [.nestedCheckouts([".build/checkouts/swift-nio/vendor/mine"])], "\(report)")
        #expect(report.notes.contains(.packageCopies([".build/checkouts/swift-nio", ".build/repositories/swift-nio-1a2b3c4d"])))
        #expect(report.status != .autoReady && !report.manualAllowed)

        var remover = Remover(git: world.fixture.git, settings: Settings(), environment: world.fixture.environment())
        remover.captureCwdIndex = { ProcessCwdIndex(entries: []) }
        await #expect(throws: RemovalError.self) {
            try await remover.remove(try await world.worktree(wt), mode: .manual, estimatedBytes: nil,
                                     knownWorktrees: try await known(world))
        }
        #expect(FileManager.default.fileExists(atPath: mine.appending(path: "work.txt").path))
    }

    /// The copy's own submodule (its `.git` file leads into the copy's `.git/modules`) is part of the copy.
    @Test func aCopysOwnSubmoduleBelongsToTheCopy() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("swiftpm")
        let (checkout, _) = try await world.fixture.xcodePackage("grpc", in: wt, base: ".build")
        let (third, _) = try await world.fixture.xcodePackage("boringssl", in: world.fixture.url, base: "upstream")
        try await world.fixture.run(["-c", "protocol.file.allow=always", "submodule", "add", "--quiet", third.path,
                                     "third_party/boringssl"], in: checkout)
        #expect(NestedRepoFinder.gitFileTarget(checkout.appending(path: "third_party/boringssl/.git"))?.path
            .contains("/.git/modules/") == true)

        let report = try await world.check(wt)
        #expect(report.blockers.isEmpty, "\(report)")
        #expect(report.status == .autoReady)
    }

    /// A `.git` file inside a copy that leads anywhere else (another repo's worktree) is not the copy's: it blocks.
    @Test func anotherGitFileInsideACopyBlocks() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("swiftpm")
        let (checkout, _) = try await world.fixture.xcodePackage("swift-nio", in: wt, base: ".build")
        let outside = try await world.fixture.makeRepo("outside", in: world.fixture.url.appending(path: "elsewhere"))
        try await world.fixture.addWorktree(to: outside, at: checkout.appending(path: "Examples/linked"), branch: "linked")

        let report = try await world.check(wt)
        #expect(report.blockers == [.nestedCheckouts([".build/checkouts/swift-nio/Examples/linked"])], "\(report)")
    }

    /// The entry cap counts the folders searched inside copies too.
    @Test func theCapCountsInsideCopies() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("swiftpm")
        let (checkout, _) = try await world.fixture.xcodePackage("swift-nio", in: wt, base: ".build")
        for index in 0..<40 { try world.fixture.write("x\n", to: "Sources/File\(index).swift", in: checkout) }
        let outsideCopies = NestedCheckoutSearch().search(wt).entries
        let report = try await world.check(wt, nestedSearch: NestedCheckoutSearch(limit: outsideCopies + 10))
        let incomplete = report.notes.compactMap { reason -> String? in
            if case .nestedSearchIncomplete(let why) = reason { return why }
            return nil
        }
        #expect(incomplete.first?.hasPrefix("inside .build/checkouts/swift-nio:") == true, "\(report)")
        #expect(!report.autoEligible)
    }

    /// A clean clone (remote, pushed tag, nothing local) whose own `.gitignore` ignores `node_modules/`, so its
    /// `git status` doesn't see what is there.
    static func cleanCloneIgnoringNodeModules(_ fixture: GitFixture, in folder: URL, at relative: String) async throws -> URL {
        let id = UUID().uuidString.prefix(8)
        let remote = fixture.remotes.appending(path: "lib-\(id).git")
        try await fixture.run(["init", "--quiet", "--bare", remote.path], in: fixture.url)
        let seed = fixture.url.appending(path: "seed-lib-\(id)")
        try await fixture.run(["clone", "--quiet", remote.path, seed.path], in: fixture.url)
        try fixture.write("node_modules/\n", to: ".gitignore", in: seed)
        try fixture.write("module.exports = 1\n", to: "index.js", in: seed)
        try await fixture.commitAll(in: seed, message: "Release")
        try await fixture.run(["tag", "1.0.0"], in: seed)
        try await fixture.run(["push", "--quiet", "origin", "main", "--tags"], in: seed)
        let clone = folder.appending(path: relative, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: clone.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await fixture.run(["clone", "--quiet", remote.path, clone.path], in: fixture.url)
        try await fixture.run(["checkout", "--quiet", "--detach", "1.0.0"], in: clone)
        return clone
    }

    /// P12b review round 2: a repo with work below a clean clone (hidden by the clone's own ignore) blocks.
    @Test func aRepoWithWorkInsideACleanCloneBlocks() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("npm")
        let lib = try await Self.cleanCloneIgnoringNodeModules(world.fixture, in: wt, at: "node_modules/lib")
        let mine = try await Self.repoWithWork(world.fixture, in: lib, at: "node_modules/mine")

        let report = try await world.check(wt)
        #expect(report.blockers == [.nestedCheckouts(["node_modules/lib/node_modules/mine"])], "\(report)")
        #expect(report.notes.contains(.nestedClones(["node_modules/lib"])))
        #expect(!report.manualAllowed && report.status != .autoReady)
        var remover = Remover(git: world.fixture.git, settings: Settings(), environment: world.fixture.environment())
        remover.captureCwdIndex = { ProcessCwdIndex(entries: []) }
        await #expect(throws: RemovalError.self) {
            try await remover.remove(try await world.worktree(wt), mode: .manual, estimatedBytes: nil,
                                     knownWorktrees: try await known(world))
        }
        #expect(FileManager.default.fileExists(atPath: mine.appending(path: "work.txt").path))
    }

    /// Inside a copy's own submodule: a repo with work there blocks too (the submodule is let go and searched).
    @Test func aRepoWithWorkInsideACopysSubmoduleBlocks() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("swiftpm")
        let (checkout, _) = try await world.fixture.xcodePackage("grpc", in: wt, base: ".build")
        let (third, _) = try await world.fixture.xcodePackage("boringssl", in: world.fixture.url, base: "upstream")
        try await world.fixture.run(["-c", "protocol.file.allow=always", "submodule", "add", "--quiet", third.path,
                                     "third_party/boringssl"], in: checkout)
        try await Self.repoWithWork(world.fixture, in: checkout, at: "third_party/boringssl/vendor/mine")

        let report = try await world.check(wt)
        #expect(report.blockers == [.nestedCheckouts([".build/checkouts/grpc/third_party/boringssl/vendor/mine"])], "\(report)")
    }
}
