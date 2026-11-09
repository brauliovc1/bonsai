@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// PLAN §8.6: one total for the Overview, the sidebar and the menu window, each byte counted once.
@Suite("What Bonsai can free")
@MainActor
struct ReclaimSummaryTests {
    /// `india`, idle 60 days, with 256 KiB of ignored node_modules in the repo folder, and its sibling worktree
    /// `india-done`, pushed and clean, idle 45 days, with 2 MiB of ignored node_modules: ready to remove whole.
    private struct World {
        let fixture: GitFixture
        /// Kept alive: its scripted runner refers back to it.
        let toolchain: FakeToolchain
        let models: ScreenModels
        let repo: URL
        let sibling: URL
    }

    private func makeWorld() async throws -> World {
        let fixture = try GitFixture()
        let aged = AgedRepos(fixture: fixture)
        let repo = try await aged.repo("india", days: 60, gitignore: ProjectFoldersDemo.gitignore, files: ["package-lock.json": "{}\n"])
        try aged.blob(in: repo, "node_modules/left-pad/index.bin", kibibytes: 256)
        let sibling = fixture.scanRoot.appending(path: "india-done", directoryHint: .isDirectory)
        try await aged.git(["worktree", "add", "--quiet", "-b", "done", sibling.path], in: repo, days: 45)
        try await aged.commitAndPush(sibling, file: "notes/done.md", branch: "done", days: 45)
        try aged.blob(in: sibling, "node_modules/react/index.bin", megabytes: 2)
        try await aged.age(sibling, days: 45)
        try await aged.age(repo, days: 60)
        let environment = fixture.environment(scanRoots: [fixture.scanRoot]).withFakeTools(docker: false, xcrun: false)
        let app = AppModel(environment: environment, git: fixture.git)
        let toolchain = FakeToolchain()
        let models = ScreenModels(app: app, runner: toolchain.runner, processes: ScriptedProcesses().source)
        await app.refresh()
        await models.overview.loadIfNeeded()
        return World(fixture: fixture, toolchain: toolchain, models: models, repo: repo, sibling: sibling)
    }

    @Test func aRemovableWorktreesDependenciesCountOnceAndTheRepoFoldersInProjectFolders() async throws {
        let world = try await makeWorld()
        defer { world.fixture.remove() }
        let projects = world.models.projects
        let summary = world.models.overview.summary

        let done = try #require(world.models.app.assessments.first { CanonicalPath.same($0.worktree.url, world.sibling) })
        #expect(done.safety.manualAllowed, "\(done.status.label)")
        let doneBytes = try #require(done.estimatedBytes)
        #expect(doneBytes >= 2 * 1024 * 1024, "its node_modules are inside its own size")
        #expect(summary.state(.worktrees) == .measured(bytes: doneBytes, count: 1))

        // Project folders lists both checkouts as idle and ready, but counts only the repo folder's.
        let ready = projects.allRows.filter(\.isReady)
        #expect(Set(ready.map(\.url.lastPathComponent)) == ["india", "india-done"])
        #expect(projects.reclaimableRows.map(\.url.lastPathComponent) == ["india"])
        let repoFolders = try #require(projects.allRows.first { CanonicalPath.same($0.url, world.repo) }).sizeBytes
        #expect(repoFolders >= 256 * 1024)
        #expect(summary.state(.projectFolders) == .measured(bytes: repoFolders, count: 1))
        #expect(summary.totalBytes == doneBytes + repoFolders, "each byte once")
        #expect(projects.idleTotal.bytes > repoFolders, "the plain idle total would have counted india-done's twice")

        // Once the worktree is gone, nothing of it is counted anywhere.
        await world.models.app.cleanupFinished(rescanWorktrees: false, removed: [done.worktree])
        let after = world.models.overview.summary
        #expect(after.bytes(.worktrees) == 0)
        #expect(after.bytes(.projectFolders) == repoFolders)
    }

    @Test func theTooltipListsTheNonZeroPartsAndTheBadgesAreTheParts() {
        let gib: Int64 = 1024 * 1024 * 1024
        let summary = ReclaimSummary([
            .worktrees: .measured(bytes: 56 * gib, count: 83),
            .projectFolders: .measuring,
            .toolCaches: .measured(bytes: 0, count: 0),
            .docker: .unavailable("Docker isn't running, so its space isn't counted."),
            .derivedData: .measured(bytes: 3 * gib, count: 12),
            .simulators: .measured(bytes: gib, count: 3),
        ])
        #expect(summary.partsHelp == """
            Worktrees: 56.0 GB
            Xcode DerivedData: 3.0 GB
            Simulators: 1.0 GB
            Not measured yet: Project folders
            """)
        #expect(!summary.partsHelp.contains("Tool caches"), "zero parts are left out")
        #expect(!summary.partsHelp.contains("Docker"))
        #expect(summary.totalBytes == 60 * gib)
        #expect(summary.nonZeroParts == [.worktrees, .derivedData, .simulators])
        #expect(summary.emptyParts == [.toolCaches])
        #expect(summary.pendingParts == [.projectFolders])

        // Each clean-up screen's badge is its parts; the rest have none.
        for section in SidebarSection.allCases {
            let bytes = section.reclaimParts.map { summary.bytes($0) }.reduce(0, +)
            #expect(section.badge(in: summary) == (bytes > 0 ? DisplayText.bytes(bytes) : nil), "\(section)")
        }
        #expect(SidebarSection.worktrees.badge(in: summary) == "56.0 GB")
        #expect(SidebarSection.dockerSimulators.badge(in: summary) == "1.0 GB", "Docker isn't counted, simulators are")
        #expect(SidebarSection.caches.badge(in: summary) == nil)
        #expect(SidebarSection.overview.badge(in: summary) == nil)
        // Every part has exactly one screen.
        let parts = SidebarSection.allCases.flatMap(\.reclaimParts)
        #expect(parts.count == ReclaimSummary.Part.allCases.count && Set(parts) == Set(ReclaimSummary.Part.allCases))
        #expect(ReclaimSummary.names([.docker, .derivedData, .simulators]) == "Docker, Xcode DerivedData or Simulators")
    }

    /// The menu window's number is the Overview's: the same summary, from the same models.
    @Test func theMenuAndTheOverviewShowTheSameTotal() async throws {
        let world = try await makeWorld()
        defer { world.fixture.remove() }
        let overview = world.models.overview
        let sidebarTotal = SidebarSection.allCases.compactMap { section -> Int64? in
            let bytes = overview.summary.bytes(section.reclaimParts)
            return bytes > 0 ? bytes : nil
        }.reduce(0, +)
        #expect(sidebarTotal == overview.summary.totalBytes, "the badges add up to the headline")
        #expect(overview.canFreeText == "Bonsai can free about \(DisplayText.bytes(overview.summary.totalBytes))")
        #expect(world.models.app.reclaimableBytes == overview.summary.bytes(.worktrees))
    }
}
