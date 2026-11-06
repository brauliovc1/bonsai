@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("SimulatorScanner")
struct SimulatorScannerTests {
    private static let xcrun = URL(fileURLWithPath: "/fake/bin/xcrun")
    private static let devicesArguments = ["simctl", "list", "devices", "-j"]
    private static let runtimesArguments = ["simctl", "runtime", "list", "-j"]

    private func script(
        devices: ProcessResult = ScriptedCommandRunner.result(stdout: SimctlParserTests.devicesJSON),
        runtimes: ProcessResult = ScriptedCommandRunner.result(stdout: SimctlParserTests.runtimesJSON)
    ) -> ScriptedCommandRunner {
        ScriptedCommandRunner { call in
            switch call.arguments {
            case Self.devicesArguments: devices
            case Self.runtimesArguments: runtimes
            default: throw ScriptedCommandRunner.StartFailure()
            }
        }
    }

    private func environment(_ home: FakeHome) -> CleanEnvironment {
        home.environment(xcrun: Self.xcrun, developerToolsInstalled: true)
    }

    @Test func availableXcodeReportsDevicesRuntimesAndFolderSizes() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        try home.addFile("Library/Developer/CoreSimulator/Devices/AAAA/data/a.bin", kibibytes: 40)
        try home.addFile("Library/Developer/CoreSimulator/Devices/BBBB/data/b.bin", kibibytes: 12)
        try home.addFile("Library/Developer/CoreSimulator/Caches/dyld/c.bin", kibibytes: 8)
        let runner = script()

        let report = await SimulatorScanner(environment: environment(home), runner: runner.runner).scan()

        #expect(report.state == .available)
        #expect(report.devicesBytes == Int64(52 * 1024))
        #expect(report.cachesBytes == Int64(8 * 1024))
        #expect(report.unavailableDevices.map(\.udid) == ["BBBB", "CCCC"])
        #expect(report.unavailableDevicesBytes == 123_456)
        #expect(report.runtimes.count == 4)
        #expect(report.runtimes.first?.displayName == "iOS 27.0 (24A434)")
        #expect(report.warnings.isEmpty, "\(report.warnings)")

        // Only the two read-only listings run, both through xcrun, in either order.
        #expect(Set(runner.calls.map(\.arguments)) == [Self.devicesArguments, Self.runtimesArguments])
        #expect(runner.calls.count == 2)
        #expect(runner.calls.allSatisfy { $0.executable == Self.xcrun })
    }

    @Test func missingCoreSimulatorFoldersHaveNoSize() async throws {
        let home = try FakeHome()
        defer { home.remove() }

        let report = await SimulatorScanner(environment: environment(home), runner: script().runner).scan()

        #expect(report.state == .available)
        #expect(report.devicesBytes == nil && report.cachesBytes == nil)
    }

    @Test func noXcodeWhenXcodeSelectFailsAndRunsNothing() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        try home.addFile("Library/Developer/CoreSimulator/Devices/AAAA/a.bin", kibibytes: 8)
        let runner = script()

        // xcrun exists but `xcode-select -p` failed.
        let environment = home.environment(xcrun: Self.xcrun, developerToolsInstalled: false)
        let report = await SimulatorScanner(environment: environment, runner: runner.runner).scan()

        #expect(report.state == .noXcode)
        #expect(report.devicesBytes == nil && report.unavailableDevices.isEmpty && report.runtimes.isEmpty)
        #expect(runner.calls.isEmpty)
    }

    @Test func noXcodeWhenXcrunIsMissing() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let runner = script()

        let environment = home.environment(xcrun: nil, developerToolsInstalled: true)
        let report = await SimulatorScanner(environment: environment, runner: runner.runner).scan()

        #expect(report.state == .noXcode)
        #expect(runner.calls.isEmpty)
    }

    @Test func aFailingDevicesListingStillReportsRuntimes() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let runner = script(devices: ScriptedCommandRunner.result(exitCode: 1, stderr: "simctl: no service"))

        let report = await SimulatorScanner(environment: environment(home), runner: runner.runner).scan()

        #expect(report.state == .available)
        #expect(report.unavailableDevices.isEmpty)
        #expect(report.runtimes.count == 4)
        #expect(report.warnings.count == 1)
        #expect(report.warnings.first?.contains("simctl: no service") == true)
    }

    @Test func unreadableOrTimedOutOutputBecomesWarnings() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let runner = script(
            devices: ScriptedCommandRunner.result(stdout: "this is not json"),
            runtimes: ScriptedCommandRunner.result(exitCode: 15, timedOut: true)
        )

        let report = await SimulatorScanner(environment: environment(home), runner: runner.runner).scan()

        #expect(report.state == .available)
        #expect(report.unavailableDevices.isEmpty && report.runtimes.isEmpty)
        #expect(report.warnings.count == 2)
        #expect(report.warnings.contains { $0.contains("timed out") })
        #expect(report.warnings.contains { $0.contains("unexpected output") })
        // Wave 4: no devices because the list couldn't be read is not "no unavailable devices".
        #expect(report.deviceListFailure?.contains("unexpected output") == true, "\(report.deviceListFailure ?? "nil")")
    }

    @Test func aFailedRuntimeListIsNotADeviceListFailure() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let runner = script(runtimes: ScriptedCommandRunner.result(exitCode: 1, stderr: "no runtimes"))

        let report = await SimulatorScanner(environment: environment(home), runner: runner.runner).scan()

        #expect(report.warnings.count == 1)
        #expect(report.deviceListFailure == nil)
        #expect(report.unavailableDevices.count == 2)
    }

    @Test func aBinaryThatCannotStartBecomesWarnings() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let runner = ScriptedCommandRunner { _ in throw ScriptedCommandRunner.StartFailure() }

        let report = await SimulatorScanner(environment: environment(home), runner: runner.runner).scan()

        #expect(report.state == .available)
        #expect(report.warnings.count == 2)
    }

    @Test func reportSurvivesAJSONRoundTrip() throws {
        let report = SimulatorReport(
            state: .available,
            devicesBytes: 10,
            cachesBytes: nil,
            unavailableDevices: [SimulatorDevice(name: "n", udid: "u", runtime: "r", sizeBytes: 3)],
            runtimes: [SimulatorRuntime(
                identifier: "i",
                version: "17.5",
                deletable: true,
                lastUsedAt: Date(timeIntervalSince1970: 1_700_000_000),
                sizeBytes: 9
            )],
            warnings: ["w"]
        )
        let data = try CleanJSON.encoder().encode(report)
        #expect(try CleanJSON.decoder().decode(SimulatorReport.self, from: data) == report)
    }
}
