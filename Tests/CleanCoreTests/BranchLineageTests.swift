@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Branch lineage", .serialized)
struct BranchLineageTests {
    @Test func reflogFactsKeepCreationDatesAndStackedFamilies() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        let git = try world.git(), catalog = try await RefCatalog.load(using: git)
        let reader = BranchLineageReader(git: git, catalog: catalog)
        let history = try await reader.load(branch: "b", base: "main")
        #expect(history.origin.source == .reflog && history.origin.parent == "refs/heads/a")
        #expect(history.origin.date == Date(timeIntervalSince1970: world.epoch + 20_000))
        #expect(history.tip.date != history.origin.date)
        #expect(history.children == ["refs/heads/c"])
        #expect(history.parentChain.branches == ["refs/heads/b", "refs/heads/a", "refs/heads/main"])
        let path = world.fixture.scanRoot.appending(path: "history-worktree")
        try await world.fixture.run(["worktree", "add", "--quiet", "-b", "worktree-child", path.path, "b"], in: world.repo,
                                    adding: world.dates(world.epoch + 40_000))
        let fresh = try world.git(), freshCatalog = try await RefCatalog.load(using: fresh)
        let child = try await BranchLineageReader(git: fresh, catalog: freshCatalog).load(branch: "worktree-child", base: "main")
        #expect(child.origin.source == .reflog && child.origin.parent == "refs/heads/b")
        #expect(child.worktree.map { CanonicalPath.same(URL(fileURLWithPath: $0), path) } == true)
    }

    @Test func expiredReflogsUseProbablyAndAvoidDescendantParentCycles() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        for name in ["a", "b", "c"] {
            try FileManager.default.removeItem(at: world.repo.appending(path: ".git/logs/refs/heads/" + name))
        }
        let git = try world.git(), catalog = try await RefCatalog.load(using: git)
        let reader = BranchLineageReader(git: git, catalog: catalog)
        let history = try await reader.load(branch: "c", base: "main")
        #expect(history.origin.source == .sharedHistory && !history.origin.isCertain)
        #expect(history.origin.reason.contains("most recent shared commit"))
        #expect(history.origin.parent == "refs/heads/b")
        #expect(history.parentChain.branches == ["refs/heads/c", "refs/heads/b", "refs/heads/a", "refs/heads/main"])
        #expect(history.parentChain.cycleAt == nil)
    }

    @Test func mergeEventUsesTheActualMergeCommitAndItsDate() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        let date = world.epoch + 50_000
        try await world.fixture.run(["merge", "--quiet", "--no-ff", "a", "-m", "Merge branch a"], in: world.repo, adding: world.dates(date))
        let mergedSHA = try await world.sha("main")
        try await world.branch("later", from: "main", date: date + 100)
        try await world.commit("later.txt", date: date + 200)
        try await world.fixture.run(["checkout", "--quiet", "main"], in: world.repo)
        try await world.fixture.run(["merge", "--quiet", "--no-ff", "later", "-m", "Later merge"], in: world.repo, adding: world.dates(date + 300))
        let git = try world.git(), catalog = try await RefCatalog.load(using: git)
        let history = try await BranchLineageReader(git: git, catalog: catalog).load(branch: "a", base: "main")
        #expect(history.merged.state == .mergeCommit)
        #expect(history.merged.commit?.sha == mergedSHA && history.merged.commit?.subject == "Merge branch a")
        #expect(history.merged.commit?.date == Date(timeIntervalSince1970: date))
    }

    @Test(arguments: ["squash", "rebase", "fast-forward"])
    func integratedChangesHaveNoInventedMergeDate(method: String) async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        switch method {
        case "squash":
            try await world.fixture.run(["merge", "--quiet", "--squash", "a"], in: world.repo)
            try await world.fixture.run(["commit", "--quiet", "-m", "Squash a"], in: world.repo, adding: world.dates(world.epoch + 50_000))
        case "rebase":
            try await world.fixture.run(["cherry-pick", try await world.sha("a")], in: world.repo, adding: world.dates(world.epoch + 50_000))
        default:
            try await world.fixture.run(["merge", "--quiet", "--ff-only", "a"], in: world.repo)
            try await world.branch("later", from: "main", date: world.epoch + 40_000)
            try await world.commit("later.txt", date: world.epoch + 50_000)
            try await world.fixture.run(["checkout", "--quiet", "main"], in: world.repo)
            try await world.fixture.run(["merge", "--quiet", "--no-ff", "later", "-m", "Unrelated merge after fast forward"], in: world.repo)
        }
        let git = try world.git(), catalog = try await RefCatalog.load(using: git)
        let history = try await BranchLineageReader(git: git, catalog: catalog).load(branch: "a", base: "main")
        #expect(history.merged.state == .changesInBase)
        #expect(history.merged.commit == nil)
    }

    @Test func mergingIntoAnotherBranchDoesNotClaimIntegrationIntoTheBase() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        try await world.branch("separate", from: "main", date: world.epoch + 40_000)
        try await world.commit("separate.txt", date: world.epoch + 50_000)
        try await world.fixture.run(["checkout", "--quiet", "b"], in: world.repo)
        try await world.fixture.run(["merge", "--quiet", "--no-ff", "separate", "-m", "Merge away from main"], in: world.repo)
        let git = try world.git(), catalog = try await RefCatalog.load(using: git)
        let history = try await BranchLineageReader(git: git, catalog: catalog).load(branch: "separate", base: "main")
        #expect(history.merged.state == .notMerged)
    }

    @Test func rewrittenParentReflogRecoversTheForkPoint() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        try await world.commit("old-main.txt", date: world.epoch + 40_000)
        let oldTip = try await world.sha("main")
        try await world.branch("rewrite-child", from: "main", date: world.epoch + 50_000)
        try await world.commit("child.txt", date: world.epoch + 60_000)
        try await world.fixture.run(["checkout", "--quiet", "main"], in: world.repo)
        try await world.fixture.run(["reset", "--hard", world.seed], in: world.repo)
        try await world.commit("new-main.txt", date: world.epoch + 70_000)
        let git = try world.git(), catalog = try await RefCatalog.load(using: git)
        let history = try await BranchLineageReader(git: git, catalog: catalog).load(branch: "rewrite-child", base: "main")
        #expect(history.forkSource == .parentReflog && history.forkPoint?.sha == oldTip)
        #expect(try await BranchGit(git: git).mergeBase("main", "rewrite-child") == world.seed)
    }
}
