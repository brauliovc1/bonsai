@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// PLAN §4.2 light clean: which folders are candidates.
@Suite("LightCleanFinder")
struct LightCleanFinderTests {
    @Test func findsIgnoredUntrackedFoldersAndSaysWhyOthersAreSkipped() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "deps")
        try world.file("node_modules/pkg/index.js", in: wt, kibibytes: 8)
        try world.file("node_modules/pkg/node_modules/inner/index.js", in: wt)
        try world.file("packages/a/node_modules/x/index.js", in: wt)
        try world.fixture.write("built\n", to: "dist/app.js", in: wt)
        try await world.fixture.commitAll(in: wt, message: "Commit the build")
        try world.file("build/out.o", in: wt)
        try FileManager.default.createDirectory(at: wt.appending(path: "packages/b"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: wt.appending(path: "packages/b/node_modules").path,
            withDestinationPath: "../a/node_modules"
        )

        let worktree = try await world.worktree(wt)
        let findings = await world.finder().candidates(in: worktree)

        #expect(findings.problem == nil)
        #expect(findings.candidates.map(\.relativePath) == ["node_modules", "packages/a/node_modules"])
        #expect(findings.candidates.map(\.name) == ["node_modules", "node_modules"])
        #expect(findings.candidates.map(\.worktreePath) == [worktree.path, worktree.path])
        #expect(findings.candidates.map(\.path) == [worktree.path + "/node_modules", worktree.path + "/packages/a/node_modules"])
        #expect(findings.candidates.map(\.estimatedBytes) == [Int64(12 * 1024), Int64(4 * 1024)])
        #expect(findings.estimatedBytes == Int64(16 * 1024))
        #expect(findings.skipped == [
            LightCleanSkip(relativePath: "build", name: "build", reason: .notIgnored),
            LightCleanSkip(relativePath: "dist", name: "dist", reason: .hasTrackedFiles),
            LightCleanSkip(relativePath: "packages/b/node_modules", name: "node_modules", reason: .symlink),
        ])
    }

    @Test func walksToDepthFourOnly() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "deep")
        try world.file("a/b/c/node_modules/x.js", in: wt)
        try world.file("a/b/c/d/node_modules/x.js", in: wt)

        let findings = await world.finder().candidates(in: try await world.worktree(wt))

        #expect(findings.candidates.map(\.relativePath) == ["a/b/c/node_modules"])
        #expect(findings.skipped.isEmpty)
    }

    @Test func worksOnTheMainCheckoutWithoutEnteringItsLinkedWorktrees() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        try world.file("node_modules/x.js", in: world.repo)
        let claude = try await world.fixture.addClaudeWorktree(to: world.repo, name: "task")
        try world.file("node_modules/y.js", in: claude)

        let main = try await world.worktree(world.repo)
        #expect(main.isMain)
        let findings = await world.finder().candidates(in: main, knownWorktrees: try await world.known())

        #expect(findings.candidates.map(\.relativePath) == ["node_modules"])
        #expect(findings.skipped.isEmpty)
        let linked = await world.finder().candidates(in: try await world.worktree(claude))
        #expect(linked.candidates.map(\.relativePath) == ["node_modules"])
    }

    @Test func missingAndBareWorktreesAreAProblemNotAnError() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "gone")
        try world.fixture.deleteFolder(wt)

        let findings = await world.finder().candidates(in: try await world.worktree(wt))
        #expect(findings.problem == "the folder is missing")
        #expect(findings.candidates.isEmpty)
    }

    @Test func aBrokenGitFileIsAGitErrorNotTheEnclosingReposAnswer() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let claude = try await world.fixture.addClaudeWorktree(to: world.repo, name: "broken")
        try world.file("node_modules/x.js", in: claude)
        let record = try await world.worktree(claude)
        // Without its `.git` file, git inside would answer for the main repo, which ignores .claude/worktrees/.
        try FileManager.default.removeItem(at: claude.appending(path: ".git"))

        let findings = await world.finder().candidates(in: record)

        #expect(findings.candidates.isEmpty)
        let skip = try #require(findings.skipped.first)
        guard case .gitError(let message) = skip.reason else {
            Issue.record("expected a git error, got \(skip.reason)")
            return
        }
        #expect(message.contains("not this worktree"), "\(message)")
    }

    @Test func aFolderNamedLikeOutputThatIsAFileIsNotACandidate() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "file")
        try world.fixture.write("not a folder\n", to: "node_modules", in: wt)

        let findings = await world.finder().candidates(in: try await world.worktree(wt))
        #expect(findings.candidates.isEmpty && findings.skipped.isEmpty)
    }

    @Test func dependencyBytesSumTheCandidatesOfEachWorktree() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        try world.file("node_modules/x.js", in: world.repo, kibibytes: 8)
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "sum")
        try world.file("node_modules/x.js", in: wt, kibibytes: 4)
        try world.file("packages/a/node_modules/y.js", in: wt, kibibytes: 4)
        let empty = try await world.fixture.addSiblingWorktree(to: world.repo, name: "empty")

        let scan = await Scanner(environment: world.fixture.environment(scanRoots: [world.fixture.scanRoot]))
            .scan(includeSizes: false, includeDependencies: true)
        let bytes = try #require(scan.dependencyBytes)
        #expect(bytes[try await world.worktree(world.repo).path] == Int64(8 * 1024))
        #expect(bytes[try await world.worktree(wt).path] == Int64(8 * 1024))
        #expect(bytes[try await world.worktree(empty).path] == nil)
        #expect(bytes.count == 2)

        let plain = await Scanner(environment: world.fixture.environment(scanRoots: [world.fixture.scanRoot]))
            .scan(includeSizes: false)
        #expect(plain.dependencyBytes == nil, "only computed when asked for")
    }
}
