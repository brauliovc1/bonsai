@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Simulators model")
@MainActor
struct SimulatorsModelTests {
    // MARK: - Simulators

    @Test func simulatorsWithoutXcode() async throws {
        let world = try DockerSimulatorsWorld(developerTools: false)
        defer { world.home.remove() }
        await world.model.refresh()

        #expect(world.model.noXcode)
        #expect(!world.model.simulatorsAvailable)
        #expect(!world.model.canDeleteUnavailable)
        #expect(world.model.unavailableDevices.isEmpty)
        #expect(world.model.unavailableBytes == nil)
        #expect(world.toolchain.calls.filter { $0.executable == FakeToolchain.xcrun }.isEmpty)
    }

    @Test func simulatorsShowSizesUnavailableDevicesAndReadOnlyRuntimes() async throws {
        let world = try DockerSimulatorsWorld()
        defer { world.home.remove() }
        try world.home.addFile("Library/Developer/CoreSimulator/Devices/AAAA/data/a.bin", kibibytes: 40)
        try world.home.addFile("Library/Developer/CoreSimulator/Caches/dyld/c.bin", kibibytes: 8)
        await world.model.refresh()

        #expect(world.model.simulatorsAvailable)
        #expect(world.model.devicesBytes == Int64(40 * 1024))
        #expect(world.model.cachesBytes == Int64(8 * 1024))
        #expect(world.model.unavailableDevices.map(\.udid) == ["CCCC", "BBBB"], "biggest first")
        #expect(world.model.unavailableBytes == 323_456)
        #expect(world.model.runtimeLines.map(\.name) == ["iOS 27.0 (24A434)"])
        #expect(DockerSimulatorsModel.runtimesHint == "Remove runtimes in Xcode > Settings > Components.")
        #expect(world.model.canDeleteUnavailable)
        #expect(world.toolchain.deleteCalls.isEmpty)
    }

    @Test func theSimulatorsSheetCarriesTheExactCommandAndRunsOnlyThat() async throws {
        let world = try DockerSimulatorsWorld()
        defer { world.home.remove() }
        await world.model.refresh()

        await world.model.beginSimulatorsDelete()
        let confirmation = try #require(world.model.simulatorsConfirmation)
        #expect(SimulatorsConfirmation.command == "xcrun simctl delete unavailable")
        #expect(confirmation.commandLine == "/fake/bin/xcrun simctl delete unavailable")
        #expect(confirmation.devices.map(\.udid) == ["CCCC", "BBBB"])
        #expect(confirmation.estimatedBytes == 323_456)
        #expect(confirmation.isAllowed)
        #expect(world.toolchain.deleteCalls.isEmpty, "opening the sheet changes nothing")

        let report = await world.model.confirmSimulatorsDelete(confirmation)

        let call = try #require(world.toolchain.deleteCalls.first)
        #expect(world.toolchain.deleteCalls.count == 1)
        #expect(call.executable == FakeToolchain.xcrun)
        #expect(call.arguments == ["simctl", "delete", "unavailable"])
        #expect(report.didRun && report.succeeded)
        #expect(report.logError == nil)
        let entry = try #require(world.app.logEntries.first)
        #expect(world.app.logEntries.count == 1)
        #expect(entry.action == .simulatorsDeleteUnavailable)
        #expect(entry.estimatedBytes == 323_456)
    }

    @Test func aDeviceThatBecameUnavailableAfterTheSheetOpenedStopsTheDelete() async throws {
        let world = try DockerSimulatorsWorld()
        defer { world.home.remove() }
        await world.model.beginSimulatorsDelete()
        let confirmation = try #require(world.model.simulatorsConfirmation)
        #expect(confirmation.devices.count == 2)

        // simctl delete unavailable would now also delete a third device the sheet never listed.
        world.toolchain.unavailable.append(("DDDD", "iPad Pro", 1_000))
        let report = await world.model.confirmSimulatorsDelete(confirmation)

        #expect(!report.didRun)
        #expect(report.error?.contains("changed since you confirmed") == true, "\(report.error ?? "")")
        #expect(world.toolchain.deleteCalls.isEmpty)
        #expect(world.app.logEntries.isEmpty)
        #expect(world.model.unavailableDevices.count == 3, "the screen shows the new list")
    }

    @Test func noUnavailableDevicesMeansNothingToDelete() async throws {
        let world = try DockerSimulatorsWorld()
        defer { world.home.remove() }
        world.toolchain.unavailable = []
        await world.model.refresh()
        #expect(!world.model.canDeleteUnavailable)

        await world.model.beginSimulatorsDelete()
        let confirmation = try #require(world.model.simulatorsConfirmation)
        #expect(!confirmation.isAllowed)
        #expect(confirmation.blocker?.contains("nothing to delete") == true)
        let report = await world.model.confirmSimulatorsDelete(confirmation)
        #expect(!report.didRun)
        #expect(world.toolchain.deleteCalls.isEmpty)
    }

    @Test func xcodeGoneAfterTheSheetOpenedStopsTheDelete() async throws {
        let world = try DockerSimulatorsWorld()
        defer { world.home.remove() }
        await world.model.beginSimulatorsDelete()
        let confirmation = try #require(world.model.simulatorsConfirmation)

        // The same confirmation, handed to a model whose environment has no Xcode.
        let other = DockerSimulatorsModel(
            app: AppModel(environment: world.home.environment().withFakeTools(developerTools: false)),
            runner: world.toolchain.runner
        )
        let report = await other.confirmSimulatorsDelete(confirmation)

        #expect(!report.didRun)
        #expect(world.toolchain.deleteCalls.isEmpty)
    }
}
