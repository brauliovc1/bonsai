@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Branch history regressions", .serialized)
struct BranchHistoryRegressionTests {
    @Test func relativeCreationRefKeepsItsRecordedForkWhenHEADMovesElsewhere() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        try await world.commit("main-1.txt", date: world.epoch + 40_000)
        let recordedFork = try await world.sha("main")
        try await world.commit("main-2.txt", date: world.epoch + 50_000)
        try await world.branch("relative-child", from: "HEAD~1", date: world.epoch + 60_000)
        try await world.commit("child.txt", date: world.epoch + 70_000)
        try await world.branch("other-line", from: world.seed, date: world.epoch + 80_000)
        try await world.commit("other-1.txt", date: world.epoch + 90_000)
        try await world.commit("other-2.txt", date: world.epoch + 100_000)
        let git = try world.git(), catalog = try await RefCatalog.load(using: git)
        let history = try await BranchLineageReader(git: git, catalog: catalog).load(branch: "relative-child", base: "main")
        #expect(history.origin.atSHA == recordedFork, "The creation reflog retains the actual fork commit")
        #expect(history.forkPoint?.sha == recordedFork, "A relative creation expression must not be evaluated against today's unrelated HEAD")
    }

    @Test func SHAOnlyCacheRefreshesWhenShallowHistoryIsDeepenedWithoutMovingRefs() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        let a = try await world.sha("a")
        let shallow = world.repo.appending(path: ".git/shallow")
        try Data((a + "\n").utf8).write(to: shallow)
        let map = BranchMap()
        let beforeGit = try world.git(), beforeCatalog = try await RefCatalog.load(using: beforeGit)
        let before = try await map.load(base: "main", catalog: beforeCatalog, using: beforeGit)
        #expect(before.entries.first { $0.name == "a" }?.metrics.problem == BranchMap.unrelated)
        try FileManager.default.removeItem(at: shallow)
        let afterGit = try world.git(), afterCatalog = try await RefCatalog.load(using: afterGit)
        let reused = try await map.load(base: "main", catalog: afterCatalog, using: afterGit)
        let fresh = try await BranchMap().load(base: "main", catalog: afterCatalog, using: afterGit)
        let expected = try #require(fresh.entries.first { $0.name == "a" })
        #expect(expected.metrics.fork?.sha == world.seed && expected.metrics.problem == nil)
        #expect(reused.entries.first { $0.name == "a" }?.metrics == expected.metrics,
                "Deepening a shallow clone changes ancestry without changing either cache-key SHA")
    }

    @Test func fastForwardThenLaterMergeDoesNotInventAnEarlierBranchMergeEvent() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        try await world.fixture.run(["merge", "--quiet", "--ff-only", "a"], in: world.repo)
        try await world.branch("unrelated-later", from: "main", date: world.epoch + 40_000)
        try await world.commit("later.txt", date: world.epoch + 50_000)
        try await world.fixture.run(["checkout", "--quiet", "main"], in: world.repo)
        try await world.fixture.run(["merge", "--quiet", "--no-ff", "unrelated-later", "-m", "Later merge, not a's merge"], in: world.repo,
                                    adding: world.dates(world.epoch + 60_000))
        let git = try world.git(), catalog = try await RefCatalog.load(using: git)
        let history = try await BranchLineageReader(git: git, catalog: catalog).load(branch: "a", base: "main")
        #expect(history.merged.state == .changesInBase && history.merged.commit == nil)
    }

    @Test func identicalTipInferenceCyclesAreExplicitAndBounded() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        try await world.fixture.run(["branch", "-f", "b", "a"], in: world.repo)
        for name in ["a", "b"] {
            try FileManager.default.removeItem(at: world.repo.appending(path: ".git/logs/refs/heads/" + name))
        }
        let git = try world.git(), catalog = try await RefCatalog.load(using: git)
        let reader = BranchLineageReader(git: git, catalog: catalog)
        let family = try await reader.family(base: "main")
        let history = try await reader.load(branch: "a", base: "main", origins: family.origins)
        #expect(history.origin.source == .sharedHistory)
        #expect(history.parentChain.cycleAt != nil)
        #expect(history.parentChain.branches.count <= catalog.refs.count)
    }

    @Test func worktreeTrackingConfigStaysDataAndAllP16ReadsPreserveMetadata() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        let worktree = world.fixture.scanRoot.appending(path: "p16-linked")
        try await world.fixture.run(["worktree", "add", "--quiet", worktree.path, "a"], in: world.repo)
        try await world.fixture.run(["config", "extensions.worktreeConfig", "true"], in: world.repo)
        try await world.fixture.run(["config", "--worktree", "branch.a.remote", "."], in: worktree)
        try await world.fixture.run(["config", "--worktree", "branch.a.merge", "refs/heads/main"], in: worktree)
        let marker = world.fixture.url.appending(path: "must-not-execute")
        let command = "touch " + marker.path
        try await world.fixture.run(["config", "--local", "core.fsmonitor", command], in: world.repo)
        try await world.fixture.run(["config", "--local", "diff.external", command], in: world.repo)
        let before = try GitMetadataSnapshot(directory: world.repo.appending(path: ".git"))
        let git = try GitReadOnly(repository: worktree, executable: world.fixture.git.executable, timeout: TestWait.limit)
        let catalog = try await RefCatalog.load(using: git)
        let map = try await BranchMap().load(base: "main", catalog: catalog, includeRemotes: true, using: git)
        let reader = BranchLineageReader(git: git, catalog: catalog)
        let family = try await reader.family(base: "main")
        _ = try await reader.timeline(entries: map.entries, origins: family.origins)
        let history = try await reader.load(branch: "a", base: "main", origins: family.origins)
        #expect(history.upstream.ref == "refs/heads/main" && history.upstream.ahead == 1)
        let safe = try String(contentsOf: git.metadata.appending(path: "config"), encoding: .utf8)
        #expect(!safe.contains(command))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(try GitMetadataSnapshot(directory: world.repo.appending(path: ".git")) == before)
    }
    @Test func cacheNamespaceDescribesTheQueriedViewRatherThanMutableOriginalMetadata() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        let a = try await world.sha("a")
        let shallow = world.repo.appending(path: ".git/shallow")
        try Data((a + "\n").utf8).write(to: shallow)
        let staleView = try world.git()
        try FileManager.default.removeItem(at: shallow)
        let map = BranchMap()
        _ = try await map.load(base: "main", catalog: RefCatalog.load(using: staleView), using: staleView)
        let freshView = try world.git(), catalog = try await RefCatalog.load(using: freshView)
        let cached = try await map.load(base: "main", catalog: catalog, using: freshView)
        let fresh = try await BranchMap().load(base: "main", catalog: catalog, using: freshView)
        #expect(cached.entries.first { $0.name == "a" }?.metrics == fresh.entries.first { $0.name == "a" }?.metrics)
    }

    @Test func remoteBranchWithoutCreationRecordUsesTheSharedHistoryFallback() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        try await world.fixture.run(["push", "--quiet", "origin", "b"], in: world.repo)
        let git = try world.git(), catalog = try await RefCatalog.load(using: git)
        let history = try await BranchLineageReader(git: git, catalog: catalog).load(branch: "origin/b", base: "main")
        #expect(history.origin.source == .sharedHistory,
                "Remote branches lack local creation records, but still have the specified probable shared-history fallback")
        #expect(history.origin.parent != nil)
    }

    @Test func implicitTrueWorktreeConfigKeepsTheActualUpstream() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        let worktree = world.fixture.scanRoot.appending(path: "p16-bare-boolean")
        try await world.fixture.run(["worktree", "add", "--quiet", worktree.path, "a"], in: world.repo)
        try await world.fixture.run(["config", "extensions.worktreeConfig", "true"], in: world.repo)
        try await world.fixture.run(["config", "--worktree", "branch.a.remote", "."], in: worktree)
        try await world.fixture.run(["config", "--worktree", "branch.a.merge", "refs/heads/main"], in: worktree)
        let config = world.repo.appending(path: ".git/config")
        let text = try String(contentsOf: config, encoding: .utf8)
        #expect(text.contains("worktreeConfig = true"))
        try Data(text.replacingOccurrences(of: "worktreeConfig = true", with: "worktreeConfig").utf8).write(to: config)
        let actual = try await world.fixture.run(["for-each-ref", "--format=%(upstream)", "refs/heads/a"], in: worktree)
        #expect(actual == "refs/heads/main", "Git itself recognizes the implicit true extension flag")
        let git = try GitReadOnly(repository: worktree, executable: world.fixture.git.executable, timeout: TestWait.limit)
        let catalog = try await RefCatalog.load(using: git)
        let history = try await BranchLineageReader(git: git, catalog: catalog).load(branch: "a", base: "main")
        #expect(history.upstream.ref == "refs/heads/main")
        #expect(history.upstream.ahead == 1)
    }

    @Test func explicitEmptyWorktreeConfigFlagRemainsFalse() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        let worktree = world.fixture.scanRoot.appending(path: "p16-empty-boolean")
        try await world.fixture.run(["worktree", "add", "--quiet", worktree.path, "a"], in: world.repo)
        try await world.fixture.run(["config", "extensions.worktreeConfig", "true"], in: world.repo)
        try await world.fixture.run(["config", "--worktree", "branch.a.remote", "."], in: worktree)
        try await world.fixture.run(["config", "--worktree", "branch.a.merge", "refs/heads/main"], in: worktree)
        let config = world.repo.appending(path: ".git/config")
        let text = try String(contentsOf: config, encoding: .utf8)
        try Data(text.replacingOccurrences(of: "worktreeConfig = true", with: "worktreeConfig =").utf8).write(to: config)
        let actual = try await world.fixture.run(["for-each-ref", "--format=%(upstream)", "refs/heads/a"], in: worktree)
        #expect(actual.isEmpty, "Explicit empty boolean is false to Git, unlike a valueless key")
        let git = try GitReadOnly(repository: worktree, executable: world.fixture.git.executable, timeout: TestWait.limit)
        let catalog = try await RefCatalog.load(using: git)
        let history = try await BranchLineageReader(git: git, catalog: catalog).load(branch: "a", base: "main")
        #expect(history.upstream.ref == nil)
    }

}
