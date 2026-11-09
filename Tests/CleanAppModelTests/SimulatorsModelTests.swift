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

    /// The review's probe: the old "fresh" list came from a full scan that waited for `du`, so a device that
    /// went unavailable meanwhile was deleted too. Now only a devices listing sits between the confirm and
    /// the delete.
    @Test func onlyAListingOfDevicesSitsBetweenTheConfirmAndTheDelete() async throws {
        let marker = FileManager.default.temporaryDirectory.appending(path: "bonsai-du-\(UUID().uuidString).log")
        let duScript = FileManager.default.temporaryDirectory.appending(path: "bonsai-du-\(UUID().uuidString).sh")
        try "#!/bin/sh\necho x >> '\(marker.path)'\nexec /usr/bin/du \"$@\"\n".write(to: duScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: duScript.path)
        defer {
            try? FileManager.default.removeItem(at: duScript)
            try? FileManager.default.removeItem(at: marker)
        }
        let world = try DockerSimulatorsWorld { $0.tools.du = duScript }
        defer { world.home.remove() }
        try FileManager.default.createDirectory(
            at: world.home.url.appending(path: "Library/Developer/CoreSimulator/Devices"), withIntermediateDirectories: true
        )
        await world.model.beginSimulatorsDelete()
        let confirmation = try #require(world.model.simulatorsConfirmation)
        let duRuns: @Sendable () -> Int = { ((try? String(contentsOf: marker, encoding: .utf8)) ?? "").split(separator: "\n").count }
        let before = duRuns()
        #expect(before > 0, "the sheet's scan measured sizes")
        let atDelete = Counter()
        world.toolchain.onCall = { call in
            if call.arguments == ["simctl", "delete", "unavailable"] { atDelete.set(duRuns()) }
        }

        let report = await world.model.confirmSimulatorsDelete(confirmation)

        #expect(report.didRun)
        #expect(atDelete.value == before, "no du ran between the confirm and the delete")
        let calls = world.toolchain.calls
        let delete = try #require(calls.firstIndex { $0.arguments == ["simctl", "delete", "unavailable"] })
        #expect(calls[delete - 1].arguments == ["simctl", "list", "devices", "-j"], "the list comes right before")
    }

    @Test func aListingThatFailsAtConfirmTimeStopsTheDelete() async throws {
        let world = try DockerSimulatorsWorld()
        defer { world.home.remove() }
        await world.model.beginSimulatorsDelete()
        let confirmation = try #require(world.model.simulatorsConfirmation)

        world.toolchain.devicesFailure = "CoreSimulatorService connection invalid"
        let report = await world.model.confirmSimulatorsDelete(confirmation)

        #expect(!report.didRun)
        #expect(report.error?.contains("could not list the devices") == true, "\(report.error ?? "")")
        #expect(world.toolchain.deleteCalls.isEmpty)
        #expect(world.app.logEntries.isEmpty)
    }

    /// Wave 4: a second confirm while the delete runs is turned away without touching the running one.
    @Test func aSecondConfirmWhileTheDeleteRunsLeavesItsProgressAlone() async throws {
        let world = try DockerSimulatorsWorld()
        defer { world.home.remove() }
        await world.model.beginSimulatorsDelete()
        let confirmation = try #require(world.model.simulatorsConfirmation)
        let gate = CallGate()
        world.toolchain.onCall = gate.hold { $0.arguments == ["simctl", "delete", "unavailable"] }
        defer { gate.release() }

        let first = Task { await world.model.confirmSimulatorsDelete(confirmation) }
        try await gate.waitUntilReached()
        #expect(world.model.isDeletingDevices)
        #expect(world.model.simulatorsReport == nil)

        let second = await world.model.confirmSimulatorsDelete(confirmation)

        #expect(!second.didRun)
        #expect(second.error?.contains("already running") == true, "\(second.error ?? "")")
        #expect(world.model.simulatorsReport == nil, "the progress page is still showing")
        #expect(world.model.isDeletingDevices)

        gate.release()
        let report = await first.value
        #expect(report.didRun && report.succeeded)
        #expect(world.model.simulatorsReport?.didRun == true)
        #expect(world.toolchain.deleteCalls.count == 1)
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

/// A value one thread sets and the test reads.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = -1

    var value: Int { lock.withLock { stored } }

    func set(_ value: Int) {
        lock.withLock { stored = value }
    }
}
