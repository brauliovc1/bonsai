@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("SimulatorCleaner")
struct SimulatorCleanerTests {
    private static let xcrun = URL(fileURLWithPath: "/usr/bin/xcrun")

    @Test func deleteArgumentsAreExactlySimctlDeleteUnavailable() {
        #expect(SimulatorCleaner.deleteUnavailableArguments == ["simctl", "delete", "unavailable"])
    }

    @Test func commandLineGoesThroughXcrun() {
        let cleaner = SimulatorCleaner(xcrun: Self.xcrun, freeSpace: ScriptedFreeSpace([nil]).probe)
        #expect(cleaner.commandLine == "/usr/bin/xcrun simctl delete unavailable")
    }

    @Test func runsExactlyTheDeleteThroughXcrunAndMeasuresFreedSpace() async throws {
        let runner = ScriptedCommandRunner { _ in ScriptedCommandRunner.result(stdout: "", stderr: "") }
        let space = ScriptedFreeSpace([10_000_000, 14_500_000])
        let cleaner = SimulatorCleaner(xcrun: Self.xcrun, runner: runner.runner, freeSpace: space.probe)

        let result = try await cleaner.run()

        #expect(runner.calls.count == 1)
        #expect(runner.calls[0].executable == Self.xcrun)
        #expect(runner.calls[0].arguments == ["simctl", "delete", "unavailable"])
        #expect(runner.calls[0].timeout == .seconds(600))
        #expect(result.succeeded)
        #expect(result.output.isEmpty)
        #expect(result.freedBytes == 4_500_000)
        #expect(result.reportedBytes == nil)
    }

    @Test func aFailedDeleteReportsExitCodeAndOutput() async throws {
        let runner = ScriptedCommandRunner { _ in
            ScriptedCommandRunner.result(exitCode: 1, stderr: "An error was encountered processing the command")
        }
        let cleaner = SimulatorCleaner(xcrun: Self.xcrun, runner: runner.runner, freeSpace: ScriptedFreeSpace([5, 5]).probe)

        let result = try await cleaner.run()

        #expect(!result.succeeded && result.exitCode == 1)
        #expect(result.output == "An error was encountered processing the command")
        #expect(result.freedBytes == 0)
    }

    @Test func aBinaryThatCannotStartThrows() async {
        let runner = ScriptedCommandRunner { _ in throw ScriptedCommandRunner.StartFailure() }
        let cleaner = SimulatorCleaner(xcrun: Self.xcrun, runner: runner.runner, freeSpace: ScriptedFreeSpace([1]).probe)

        await #expect(throws: ScriptedCommandRunner.StartFailure.self) {
            _ = try await cleaner.run()
        }
    }

    @Test func buildingFromAnEnvironmentNeedsXcode() throws {
        let home = try FakeHome()
        defer { home.remove() }

        #expect(SimulatorCleaner(environment: home.environment(xcrun: Self.xcrun, developerToolsInstalled: false)) == nil)
        #expect(SimulatorCleaner(environment: home.environment(xcrun: nil, developerToolsInstalled: true)) == nil)
        let cleaner = try #require(
            SimulatorCleaner(environment: home.environment(xcrun: Self.xcrun, developerToolsInstalled: true))
        )
        #expect(cleaner.xcrun == Self.xcrun)
    }
}
