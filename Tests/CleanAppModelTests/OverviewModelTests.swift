@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Overview model")
@MainActor
struct OverviewModelTests {
    @MainActor private struct World {
        let demo: DemoWorld
        let toolchain: FakeToolchain
        let models: ScreenModels
        var app: AppModel { models.app }
        var overview: OverviewModel { models.overview }
    }

    /// The demo world, a DerivedData folder with two orphans (40 and 100 KiB) and one live project, and the
    /// scripted docker (6.2 GB prunable) and xcrun (two unavailable devices, 323,456 bytes).
    private func makeWorld(configure: (FakeToolchain) -> Void = { _ in }) async throws -> World {
        let demo = try await DemoWorld.build()
        let toolchain = FakeToolchain()
        configure(toolchain)
        let environment = demo.fixture.environment(scanRoots: [demo.folder]).withFakeTools()
        let app = AppModel(environment: environment, git: demo.fixture.git)
        let root = DerivedDataFixture.root(in: demo.fixture.home)
        try DerivedDataFixture.entry(in: root, "Gone-aaa", workspace: goneWorkspace("A"), kibibytes: 40)
        try DerivedDataFixture.entry(in: root, "Gone-bbb", workspace: goneWorkspace("B"), kibibytes: 100)
        try DerivedDataFixture.entry(in: root, "Live-ccc", workspace: "/usr/bin", kibibytes: 500)
        let models = ScreenModels(app: app, runner: toolchain.runner, processes: ScriptedProcesses().source)
        return World(demo: demo, toolchain: toolchain, models: models)
    }

    /// PLAN §8.3: "Clean up" then "History and info", in this order, every icon different.
    @Test func theWindowOpensOnTheOverviewAndTheSidebarIsInTwoGroups() {
        #expect(NavigationModel().section == .overview)
        #expect(SidebarSection.Group.allCases.map(\.title) == ["Clean up", "History and info"])
        #expect(SidebarSection.Group.cleanUp.sections.map(\.title) == [
            "Overview", "Worktrees", "Project folders", "Tool caches", "Docker & Simulators", "Xcode DerivedData",
        ])
        #expect(SidebarSection.Group.historyAndInfo.sections.map(\.title) == ["Recently removed", "Claude usage"])
        #expect(SidebarSection.allCases == SidebarSection.Group.allCases.flatMap(\.sections))
        #expect(Set(SidebarSection.allCases.map(\.systemImage)).count == SidebarSection.allCases.count)
        #expect(SidebarSection.Group.historyAndInfo.sections.allSatisfy { $0.reclaimParts.isEmpty })
    }

    @Test func eachPartSumsItsScreensOwnNumbers() async throws {
        let world = try await makeWorld()
        defer { world.demo.remove() }
        await world.overview.refresh()
        let summary = world.overview.summary

        // Worktrees: what a removal by hand accepts, the same rows as "Can remove".
        let removable = world.models.worktrees.linkedRows.filter(\.canRemove)
        #expect(summary.state(.worktrees) == .measured(
            bytes: removable.compactMap(\.sizeBytes).reduce(0, +), count: world.models.worktrees.count(.canRemove)
        ))
        // DerivedData: only the two orphans, not the live project.
        let orphans = try #require(world.models.derivedData.report).orphans
        #expect(summary.state(.derivedData) == .measured(bytes: orphans.compactMap(\.bytes).reduce(0, +), count: 2))
        #expect(summary.bytes(.derivedData) < 500 * 1024, "the live project's 500 KiB is not counted")
        // Docker: what `docker system prune -f` can free (volumes left out): 5.2 GB images + 1 GB build cache.
        #expect(summary.bytes(.docker) == 6_200_000_000)
        #expect(summary.state(.simulators) == .measured(bytes: 323_456, count: 2))
        // Nothing idle 30+ days in the demo world, and no cache in its home.
        #expect(summary.state(.projectFolders) == .measured(bytes: 0, count: 0))
        #expect(summary.state(.toolCaches) == .measured(bytes: 0, count: 0))
        #expect(summary.totalBytes == ReclaimSummary.Part.allCases.map { summary.bytes($0) }.reduce(0, +))
        #expect(summary.pendingParts.isEmpty)
        #expect(world.overview.canFreeText == "Bonsai can free about \(DisplayText.bytes(summary.totalBytes))")
    }

    /// Only categories with something to free get a card, largest first; the empty ones share one line.
    @Test func cardsOnlyForWhatCanBeFreedLargestFirst() async throws {
        let world = try await makeWorld()
        defer { world.demo.remove() }
        await world.overview.refresh()
        let cards = world.overview.cards
        #expect(cards.map(\.category) == [.docker, .worktrees, .xcode])
        #expect(cards.map(\.bytes) == cards.map(\.bytes).sorted(by: >))
        #expect(cards.allSatisfy { $0.bytes > 0 })
        let xcode = try #require(world.overview.card(.xcode))
        #expect(xcode.bytes == world.overview.summary.bytes([.derivedData, .simulators]))
        #expect(xcode.detail == "2 folders of deleted projects' DerivedData and 2 unavailable simulators")
        #expect(world.overview.card(.worktrees)?.detail == "7 worktrees you can remove; branches are kept")
        #expect(world.overview.card(.projectFolders) == nil && world.overview.card(.toolCaches) == nil)
        #expect(world.overview.nothingText == "Nothing to clean in Project folders or Tool caches.")
        #expect(world.overview.notCountedText == nil && world.overview.measuringText == nil)

        // Nothing at all: no card, and the headline says so instead of "about 0 KB".
        world.overview.summaryOverride = ReclaimSummary(Dictionary(uniqueKeysWithValues: ReclaimSummary.Part.allCases.map {
            ($0, .measured(bytes: 0, count: 0))
        }))
        #expect(world.overview.cards.isEmpty)
        #expect(world.overview.canFreeText == "Nothing to clean right now")
        #expect(world.overview.nothingText == "Nothing to clean in Worktrees, Project folders, Tool caches, Docker, "
            + "Xcode DerivedData or Simulators.")
    }

    /// Each card's button opens its screen already filtered to what the card counted.
    @Test func eachCardOpensItsScreenOnWhatItCounted() async throws {
        let world = try await makeWorld()
        defer { world.demo.remove() }
        await world.overview.refresh()
        let navigation = world.models.navigation
        let worktrees = world.models.worktrees

        worktrees.filter = .all
        worktrees.searchText = "beacon"
        world.overview.open(.worktrees)
        #expect(navigation.section == .worktrees)
        #expect(worktrees.filter == .canRemove && worktrees.searchText.isEmpty)
        #expect(worktrees.rows.count == world.overview.summary.count(.worktrees))

        world.models.projects.filter = .all
        world.overview.open(.projectFolders)
        #expect(navigation.section == .projects && world.models.projects.filter == .canFree)

        world.overview.open(.toolCaches)
        #expect(navigation.section == .caches)
        #expect(world.models.caches.selection == Set(world.models.caches.readyRows.map(\.id)))

        world.overview.open(.docker)
        #expect(navigation.section == .dockerSimulators)

        world.models.derivedData.selection = []
        world.overview.open(.xcode)
        #expect(navigation.section == .derivedData)
        #expect(world.models.derivedData.selection == world.models.derivedData.selectableIDs)
        #expect(world.models.derivedData.selectedOrphans.count == 2)

        // Xcode with only simulators to free opens Docker & Simulators.
        world.overview.summaryOverride = ReclaimSummary([
            .derivedData: .measured(bytes: 0, count: 0), .simulators: .measured(bytes: 1_000, count: 1),
        ])
        navigation.show(.overview)
        world.overview.open(.xcode)
        #expect(navigation.section == .dockerSimulators)
    }

    @Test func partsThatCantBeCountedSayWhy() async throws {
        let world = try await makeWorld { $0.dockerRunning = false }
        defer { world.demo.remove() }
        // Before any scan: nothing is known, so nothing is "nothing to clean" either.
        #expect(world.overview.summary.pendingParts == ReclaimSummary.Part.allCases)
        #expect(world.overview.nothingText == nil)
        #expect(world.overview.cards.isEmpty)
        #expect(world.overview.measuringText?.hasPrefix("Measuring Worktrees, Project folders") == true)
        #expect(world.overview.canFreeText == "Looking for space to free…")

        await world.overview.refresh()
        #expect(world.overview.summary.state(.docker) == .unavailable("Docker isn't running, so its space isn't counted."))
        #expect(world.overview.notCountedText == "Docker isn't running, so its space isn't counted.")
        #expect(world.overview.card(.docker) == nil)
        #expect(world.overview.nothingText?.contains("Docker") == false, "not counted is not nothing")
    }

    /// Wave 4: a failed `docker system df` or `simctl list` is "couldn't read" with the reason, not a 0.
    @Test func aFailedDockerOrSimulatorReadIsNotShownAsZero() async throws {
        let world = try await makeWorld {
            $0.dfFailure = "request returned 500"
            $0.devicesFailure = "CoreSimulatorService connection invalid"
        }
        defer { world.demo.remove() }

        await world.overview.refresh()
        let summary = world.overview.summary
        guard case .unavailable(let docker) = summary.state(.docker),
              case .unavailable(let simulators) = summary.state(.simulators) else {
            Issue.record("expected both unavailable: \(summary.states)")
            return
        }
        #expect(docker.contains("request returned 500"), "\(docker)")
        #expect(simulators.contains("CoreSimulatorService connection invalid"), "\(simulators)")
        #expect(!(world.overview.nothingText ?? "").contains("Docker"))
        // The screen's own numbers agree: unknown, not zero.
        #expect(world.models.dockerSimulators.dockerReclaimableBytes == nil)
        #expect(world.models.dockerSimulators.unavailableBytes == nil)

        // And when the reads work again the numbers are back.
        world.toolchain.dfFailure = nil
        world.toolchain.devicesFailure = nil
        await world.overview.refresh()
        #expect(world.overview.summary.bytes(.docker) > 0)
        #expect(world.overview.summary.bytes(.simulators) == 323_456)
    }

    /// The window (and the menu window) measure what the total needs once, Project folders included.
    @Test func loadingMeasuresEveryPartOnceAndRefreshScansAgain() async throws {
        let world = try await makeWorld()
        defer { world.demo.remove() }
        await world.app.refresh()
        let scans = world.app.scanCount
        await world.overview.loadIfNeeded()
        #expect(world.models.derivedData.report != nil)
        #expect(world.models.dockerSimulators.docker != nil)
        #expect(world.models.dockerSimulators.simulators != nil)
        #expect(world.models.caches.report != nil)
        #expect(world.models.projects.report != nil, "Project folders are part of the total now")
        #expect(world.app.scanCount == scans, "loadIfNeeded leaves the worktree scan to the app")
        #expect(world.overview.summary.pendingParts.isEmpty)

        await world.overview.refresh()
        #expect(world.app.scanCount == scans + 1)
        #expect(!world.overview.isRefreshing)
    }

    /// The bar: used space, the part Bonsai can free inside it, free space; never more to free than is used.
    @Test func theBarSplitsUsedSpace() {
        let gib: Int64 = 1024 * 1024 * 1024
        guard let space = SpaceBreakdown(free: 22 * gib, total: 460 * gib, canFree: 140 * gib) else {
            Issue.record("a known disk has a breakdown")
            return
        }
        #expect(space.usedBytes == 438 * gib)
        #expect(abs(space.usedFraction + space.canFreeFraction + space.freeFraction - 1) < 1e-9)
        #expect(space.canFreeText == "Can free 140.0 GB")
        #expect(SpaceBreakdown(free: 10 * gib, total: 20 * gib, canFree: 50 * gib)?.canFreeBytes == 10 * gib)
        #expect(SpaceBreakdown(free: nil, total: 20 * gib, canFree: 0) == nil)
    }
}
