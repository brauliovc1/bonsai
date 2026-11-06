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
        return World(demo: demo, toolchain: toolchain, models: ScreenModels(app: app, runner: toolchain.runner))
    }

    @Test func theWindowOpensOnTheOverviewAndTheSidebarIsInOrder() {
        #expect(NavigationModel().section == .overview)
        #expect(SidebarSection.allCases.map(\.title) == [
            "Overview", "Worktrees", "Xcode DerivedData", "Docker & Simulators", "Claude usage", "Recently removed",
        ])
        #expect(Set(SidebarSection.allCases.map(\.systemImage)).count == SidebarSection.allCases.count)
    }

    @Test func eachRowSumsItsCategoryFromTheReports() async throws {
        let world = try await makeWorld()
        defer { world.demo.remove() }
        await world.overview.refresh()

        let rows = world.overview.rows
        #expect(rows.map(\.kind) == [
            .autoReadyWorktrees, .safeWorktrees, .lightClean, .orphanedDerivedData, .docker, .simulators,
        ])

        // Worktrees: the same estimates the Worktrees screen shows, by status.
        let worktreeRows = world.models.worktrees.allRows
        let autoReady = worktreeRows.filter { $0.tone == .autoReady }
        let safe = worktreeRows.filter { $0.tone == .safe }
        #expect(!autoReady.isEmpty && !safe.isEmpty)
        let auto = world.overview.row(.autoReadyWorktrees)
        #expect(auto.bytes == autoReady.compactMap(\.sizeBytes).reduce(0, +))
        #expect(auto.detail == DisplayText.worktrees(autoReady.count))
        #expect(auto.title == "Worktrees ready for auto mode")
        let other = world.overview.row(.safeWorktrees)
        #expect(other.bytes == safe.compactMap(\.sizeBytes).reduce(0, +))
        #expect(other.detail == DisplayText.worktrees(safe.count))
        #expect(other.title == "Other safe worktrees")

        // DerivedData: only the two orphans, not the live project.
        let orphans = try #require(world.models.derivedData.report).orphans
        #expect(orphans.count == 2)
        let derived = world.overview.row(.orphanedDerivedData)
        #expect(derived.bytes == orphans.compactMap(\.bytes).reduce(0, +))
        #expect((derived.bytes ?? 0) < 500 * 1024, "the live project's 500 KiB is not counted")
        #expect(derived.detail == "2 folders")

        // Docker: what `docker system prune -f` can free (volumes left out): 5.2 GB images + 1 GB build cache.
        let docker = world.overview.row(.docker)
        #expect(docker.bytes == 6_200_000_000)
        #expect(docker.bytes == world.models.dockerSimulators.docker?.pruneCeilingBytes)

        // Simulators: the two unavailable devices.
        let simulators = world.overview.row(.simulators)
        #expect(simulators.bytes == 323_456)
        #expect(simulators.detail == "2 devices")

        #expect(OverviewModel.autoModeText == "Auto mode: off")
        #expect(world.overview.disk.freeBytes != nil)
    }

    @Test func lightCleanCountsDependenciesOfWorktreesIdleSevenDaysOrMore() async throws {
        let world = try await makeWorld()
        defer { world.demo.remove() }
        await world.overview.refresh()

        // Not measured yet: no number, and the row says when it will be.
        let before = world.overview.row(.lightClean)
        #expect(before.bytes == nil)
        #expect(before.detail.contains("Measured when you open Worktrees"))
        #expect(before.title.contains("7+ days"))

        await world.models.worktrees.computeDependencies()
        let rows = world.models.worktrees.allRows
        let web = try #require(rows.first { $0.url.lastPathComponent == "cobalt-web" })
        let swift = try #require(rows.first { $0.url.lastPathComponent == "cobalt-swift" })
        #expect((web.dependencyBytes ?? 0) > 19 * 1024 * 1024)
        #expect(web.idleDays == 5)
        #expect(swift.idleDays == 12)

        let row = world.overview.row(.lightClean)
        let expected = rows.filter { ($0.idleDays ?? -1) >= 7 }.compactMap(\.dependencyBytes).reduce(0, +)
        #expect(row.bytes == expected)
        #expect(row.bytes == swift.dependencyBytes, "only cobalt-swift is both idle 7+ days and has folders to delete")
        #expect((row.bytes ?? 0) < 19 * 1024 * 1024, "the 5-day-idle worktree's 20 MB is left out")
    }

    @Test func eachJumpSelectsItsSidebarScreen() async throws {
        let world = try await makeWorld()
        defer { world.demo.remove() }
        let expected: [OverviewRow.Kind: SidebarSection] = [
            .autoReadyWorktrees: .worktrees,
            .safeWorktrees: .worktrees,
            .lightClean: .worktrees,
            .orphanedDerivedData: .derivedData,
            .docker: .dockerSimulators,
            .simulators: .dockerSimulators,
        ]
        #expect(Set(expected.keys) == Set(OverviewRow.Kind.allCases))
        for (kind, section) in expected {
            world.models.navigation.show(.overview)
            #expect(world.models.navigation.section == .overview)
            world.overview.jump(to: kind)
            #expect(world.models.navigation.section == section, "\(kind)")
            #expect(world.overview.row(kind).destination == section)
        }
    }

    @Test func rowsWithoutANumberSayWhy() async throws {
        let world = try await makeWorld { $0.dockerRunning = false }
        defer { world.demo.remove() }
        // Before any scan.
        #expect(world.overview.row(.docker).detail == "Not scanned yet.")
        #expect(world.overview.row(.orphanedDerivedData).bytes == nil)
        #expect(world.overview.row(.autoReadyWorktrees).bytes == nil)
        #expect(world.overview.row(.autoReadyWorktrees).sizeText == "–")

        await world.overview.refresh()
        let docker = world.overview.row(.docker)
        #expect(docker.bytes == nil)
        #expect(docker.detail == "Docker isn't running.")
        #expect(docker.destination == .dockerSimulators)
    }

    /// Wave 4: a failed `docker system df` or `simctl list` is "couldn't read" with the reason, not a 0.
    @Test func aFailedDockerOrSimulatorReadIsNotShownAsZero() async throws {
        let world = try await makeWorld {
            $0.dfFailure = "request returned 500"
            $0.devicesFailure = "CoreSimulatorService connection invalid"
        }
        defer { world.demo.remove() }

        await world.overview.refresh()

        let docker = world.overview.row(.docker)
        #expect(docker.bytes == nil && docker.sizeText == "–", "\(docker.sizeText)")
        #expect(docker.detail.hasPrefix("Couldn't read: "), "\(docker.detail)")
        #expect(docker.detail.contains("request returned 500"), "\(docker.detail)")
        let simulators = world.overview.row(.simulators)
        #expect(simulators.bytes == nil && simulators.sizeText == "–", "\(simulators.sizeText)")
        #expect(simulators.detail.hasPrefix("Couldn't read: "), "\(simulators.detail)")
        #expect(simulators.detail.contains("CoreSimulatorService connection invalid"), "\(simulators.detail)")
        // The screen's own numbers agree: unknown, not zero.
        #expect(world.models.dockerSimulators.dockerReclaimableBytes == nil)
        #expect(world.models.dockerSimulators.unavailableBytes == nil)
        #expect(world.models.dockerSimulators.dockerWarnings.contains { $0.contains("request returned 500") })

        // And when the reads work again the numbers are back.
        world.toolchain.dfFailure = nil
        world.toolchain.devicesFailure = nil
        await world.overview.refresh()
        #expect(world.overview.row(.docker).bytes != nil)
        #expect(world.overview.row(.simulators).bytes == 323_456)
    }

    @Test func refreshScansEverythingTheOverviewSums() async throws {
        let world = try await makeWorld()
        defer { world.demo.remove() }
        let scans = world.app.scanCount
        await world.overview.loadIfNeeded()
        #expect(world.models.derivedData.report != nil)
        #expect(world.models.dockerSimulators.docker != nil)
        #expect(world.models.dockerSimulators.simulators != nil)
        #expect(world.app.scanCount == scans, "loadIfNeeded leaves the worktree scan to the app")

        await world.overview.refresh()
        #expect(world.app.scanCount == scans + 1)
        #expect(!world.overview.isRefreshing)
        #expect(world.app.lastScanAt != nil)
    }
}
