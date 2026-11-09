@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// P12b review (11-09, P0): the search goes on inside each package copy. A repo found there is not a copy and keeps
/// the §4.1 rule; a `.git` file leading into the copy's own `.git/modules` belongs to the copy.
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
}
