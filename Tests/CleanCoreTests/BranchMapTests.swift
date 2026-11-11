@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Branch map", .serialized)
struct BranchMapTests {
    @Test func reportsDistancesForkDatesWorktreeKindsAndRemoteToggle() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        try await world.commit("main-only.txt", date: world.epoch + 40_000)
        let cursor = world.fixture.environment().cursorWorktreesDirectory.appending(path: "history/detached")
        try await world.fixture.addWorktree(to: world.repo, at: cursor, detached: true)
        let git = try world.git()
        let catalog = try await RefCatalog.load(using: git)
        let map = BranchMap()
        let result = try await map.load(base: "main", catalog: catalog, using: git)
        let c = try #require(result.entries.first { $0.name == "c" })
        #expect(c.metrics.ahead == 3 && c.metrics.behind == 1)
        #expect(c.metrics.fork?.sha == world.seed && c.metrics.fork?.date == Date(timeIntervalSince1970: world.epoch))
        #expect(c.metrics.tip?.date == Date(timeIntervalSince1970: world.epoch + 30_100))
        #expect(c.metrics.commits.count == 3)
        #expect(result.entries.contains { $0.kind == .cursor && $0.worktree.map { CanonicalPath.same(URL(fileURLWithPath: $0), cursor) } == true })
        #expect(!result.entries.contains { $0.kind == .remote })
        let remotes = try await map.load(base: "main", catalog: catalog, includeRemotes: true, using: git)
        #expect(remotes.entries.contains { $0.ref == "refs/remotes/origin/main" })
        #expect(!remotes.entries.contains { $0.ref == "refs/remotes/origin/HEAD" })
        #expect(result.entries.first { $0.name == "main" }?.metrics.isMerged == true)
    }

    @Test func cacheReusesUnchangedPairsAndInvalidatesMovedBranchesAndBase() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        let map = BranchMap()
        let first = try world.git()
        _ = try await map.load(base: "main", catalog: RefCatalog.load(using: first), using: first)
        let count = await map.computations
        let again = try world.git()
        _ = try await map.load(base: "main", catalog: RefCatalog.load(using: again), using: again)
        #expect(await map.computations == count)
        #expect(await map.cacheHits > 0)
        try await world.fixture.run(["checkout", "--quiet", "a"], in: world.repo)
        try await world.commit("a-new.txt", date: world.epoch + 50_000)
        let moved = try world.git()
        _ = try await map.load(base: "main", catalog: RefCatalog.load(using: moved), using: moved)
        #expect(await map.computations == count + 1)
        try await world.fixture.run(["checkout", "--quiet", "main"], in: world.repo)
        try await world.commit("main-new.txt", date: world.epoch + 60_000)
        let baseMoved = try world.git()
        _ = try await map.load(base: "main", catalog: RefCatalog.load(using: baseMoved), using: baseMoved)
        #expect(await map.computations > count + 1)
    }

    @Test func unrelatedBranchesAreReportedAndCancellationPropagates() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        try await world.fixture.run(["checkout", "--quiet", "--orphan", "island"], in: world.repo)
        try await world.fixture.run(["rm", "-rf", "."], in: world.repo)
        try await world.commit("island.txt", date: world.epoch + 50_000)
        try await world.fixture.run(["checkout", "--quiet", "main"], in: world.repo)
        let git = try world.git(), catalog = try await RefCatalog.load(using: git)
        let map = BranchMap()
        let result = try await map.load(base: "main", catalog: catalog, using: git)
        let island = try #require(result.entries.first { $0.name == "island" })
        #expect(island.metrics.problem == BranchMap.unrelated && island.metrics.fork == nil && !island.metrics.isMerged)
        let history = try await BranchLineageReader(git: git, catalog: catalog).load(branch: "island", base: "main")
        #expect(history.origin.source == .unknown && !history.problems.isEmpty)
        let task = Task { try await map.load(base: "main", catalog: catalog, using: git) }
        task.cancel()
        do { _ = try await task.value; Issue.record("cancelled map load must not publish a result") }
        catch is CancellationError {} catch { Issue.record("unexpected cancellation error: \(error)") }
    }
    @Test func timelineLeavesTheActualParentAndCapsDotsWithTheFullCount() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        let tree = try await world.sha("main^{tree}")
        var tip = world.seed
        for index in 1...80 {
            tip = try await world.fixture.run(["commit-tree", tree, "-p", tip, "-m", "Long branch \(index)"], in: world.repo,
                                              adding: world.dates(world.epoch + Double(index) * 1000))
        }
        try await world.fixture.run(["update-ref", "refs/heads/long", tip], in: world.repo)
        let git = try world.git(), catalog = try await RefCatalog.load(using: git)
        let map = try await BranchMap().load(base: "main", catalog: catalog, using: git)
        let reader = BranchLineageReader(git: git, catalog: catalog)
        let family = try await reader.family(base: "main")
        let timeline = try await reader.timeline(entries: map.entries, origins: family.origins)
        #expect(timeline["refs/heads/c"]?.fork?.sha == (try await world.sha("b")))
        #expect(timeline["refs/heads/c"]?.commitCount == 1)
        #expect(timeline["refs/heads/c"]?.commits.count == 1)
        #expect(timeline["refs/heads/long"]?.commitCount == 80)
        #expect(timeline["refs/heads/long"]?.commits.count == BranchMap.dotLimit)
    }

}
