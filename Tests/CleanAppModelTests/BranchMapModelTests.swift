@testable import CleanAppModel
@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Branch map model", .serialized)
@MainActor
struct BranchMapModelTests {
    @Test func closedMapStaysLazyAndRemembersItsPresentation() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        let app = makeApp(world.fixture)
        let compare = CompareModel(app: app)
        await compare.configure(repo: world.repo.path, base: "main", compare: .ref("a"))
        let model = compare.branches
        #expect(!model.isOpen && model.snapshot == nil && model.history == nil)
        #expect(await model.cache.computations == 0)
        #expect(model.collapsedSummary.contains("4 branches"))
        await model.setOpen(true)
        #expect(model.snapshot?.entries.count == 4 && !model.isLoading)
        await model.setIncludesRemotes(true)
        #expect(model.snapshot?.entries.contains { $0.kind == .remote } == true)
        await model.setLayout(.timeline)
        #expect(model.family != nil)
        model.sort = .name
        await model.setOpen(false)
        #expect(!model.isOpen && model.includesRemotes && model.layout == .timeline && model.sort == .name)
    }

    @Test func pickingAStackedBranchSetsCompareAndOpensItsHistory() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        let compare = CompareModel(app: makeApp(world.fixture))
        await compare.configure(repo: world.repo.path, base: "main", compare: .ref("a"))
        await compare.branches.setOpen(true)
        await compare.branches.pick("refs/heads/b")
        #expect(compare.compare == .ref("refs/heads/b"))
        #expect(compare.branches.showsHistory && compare.branches.history?.origin.parent == "refs/heads/a")
        #expect(compare.branches.history?.children == ["refs/heads/c"])
        #expect(!compare.branches.isLoadingHistory)
    }

    @Test func choosingTheCompareSideOpensHistoryWithoutLoadingTheClosedMap() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        let compare = CompareModel(app: makeApp(world.fixture))
        await compare.configure(repo: world.repo.path, base: "main", compare: .ref("a"))
        compare.compare = .ref("c")
        await compare.refresh()
        #expect(compare.branches.showsHistory && compare.branches.history?.branch == "refs/heads/c")
        #expect(compare.branches.snapshot == nil && !compare.branches.isOpen)
        #expect(await compare.branches.cache.computations == 0)
    }

    @Test func switchingFromListToTimelineLoadsCommitsAfterHistoryLoadedTheFamily() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        let compare = CompareModel(app: makeApp(world.fixture))
        _ = compare.branches
        await compare.configure(repo: world.repo.path, base: "main", compare: .ref("c"))
        let model = compare.branches
        #expect(model.history?.branch == "refs/heads/c")
        await model.setOpen(true)
        #expect(model.layout == .list && model.family != nil && model.timeline.isEmpty)

        await model.setLayout(.timeline)

        let timeline = try #require(model.timeline["refs/heads/c"])
        #expect(timeline.fork?.sha == (try await world.sha("b")))
        #expect(timeline.commitCount == 1 && timeline.commits.count == 1)
        #expect(timeline.commits.first?.sha == (try await world.sha("c")))
    }

    @Test func timelineConnectsOnlyKnownForksToDisplayedParentsOrTheSelectedBase() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        try await world.branch("remote-child", from: "origin/main", date: world.epoch + 40_000)
        try await world.commit("remote.txt", date: world.epoch + 40_100)
        try await world.branch("temporary-parent", from: "main", date: world.epoch + 50_000)
        try await world.commit("parent.txt", date: world.epoch + 50_100)
        try await world.branch("survivor", from: "temporary-parent", date: world.epoch + 60_000)
        try await world.commit("survivor.txt", date: world.epoch + 60_100)
        try await world.fixture.run(["branch", "-D", "temporary-parent"], in: world.repo)
        try await world.fixture.run(["checkout", "--quiet", "--orphan", "disconnected"], in: world.repo)
        try await world.fixture.run(["rm", "--quiet", "-rf", "."], in: world.repo)
        try await world.commit("orphan.txt", date: world.epoch + 70_100)
        try await world.fixture.run(["checkout", "--quiet", "main"], in: world.repo)
        let compare = CompareModel(app: makeApp(world.fixture))
        await compare.configure(repo: world.repo.path, base: "main", compare: .ref("c"))
        let model = compare.branches
        await model.setOpen(true)
        await model.setLayout(.timeline)

        #expect(model.timelineParent(for: "refs/heads/a") == .base)
        #expect(model.timelineParent(for: "refs/heads/c") == .branch("refs/heads/b"))
        #expect(model.timelineParent(for: "refs/heads/remote-child") == nil)
        #expect(model.timelineParent(for: "refs/heads/survivor") == nil)
        #expect(model.timeline["refs/heads/disconnected"]?.fork == nil)
        #expect(model.snapshot?.entries.first { $0.ref == "refs/heads/disconnected" }?.metrics.tip != nil)
        #expect(model.timelineParent(for: "refs/heads/disconnected") == nil)

        await model.setIncludesRemotes(true)
        #expect(model.timelineParent(for: "refs/heads/remote-child") == .branch("refs/remotes/origin/main"))
        await model.setIncludesRemotes(false)
        await compare.configure(repo: world.repo.path, base: "origin/main", compare: .ref("c"))
        #expect(model.timelineParent(for: "refs/heads/remote-child") == .base)
    }

    @Test func historyWorktreeLinkRevealsTheMatchingRow() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        let path = world.fixture.scanRoot.appending(path: "history-b")
        try await world.fixture.run(["worktree", "add", "--quiet", path.path, "b"], in: world.repo)
        let app = makeApp(world.fixture)
        await app.refresh()
        let worktrees = WorktreesModel(app: app)
        let compare = CompareModel(app: app)
        await compare.configure(repo: world.repo.path, base: "main", compare: .ref("a"))
        await compare.branches.pick("refs/heads/b")
        let location = try #require(compare.branches.history?.worktree)
        worktrees.revealWorktree(location)
        #expect(worktrees.filter == .all && worktrees.isShowingDetails)
        #expect(worktrees.selection.contains { CanonicalPath.same(URL(fileURLWithPath: $0.path), path) })
    }
}
