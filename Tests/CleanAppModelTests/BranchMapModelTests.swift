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
