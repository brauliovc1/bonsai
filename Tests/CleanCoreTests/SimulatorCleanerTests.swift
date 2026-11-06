@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("SimulatorCleaner")
struct SimulatorCleanerTests {
    /// A path that does not exist: even a runner mistake could not start a real xcrun.
    private static let xcrun = URL(fileURLWithPath: "/fake/bin/xcrun")

    private func cleaner(_ runner: ScriptedCommandRunner, freeSpace: [Int64?] = [1, 1]) -> SimulatorCleaner {
        SimulatorCleaner(xcrun: Self.xcrun, runner: runner.runner, freeSpace: ScriptedFreeSpace(freeSpace).probe)
    }

    @Test func deleteArgumentsAreExactlySimctlDeleteUnavailable() {
        #expect(SimulatorCleaner.deleteUnavailableArguments == ["simctl", "delete", "unavailable"])
    }

    @Test func commandLineGoesThroughXcrun() {
        let runner = ScriptedCommandRunner { _ in ScriptedCommandRunner.result() }
        #expect(cleaner(runner).commandLine == "/fake/bin/xcrun simctl delete unavailable")
    }

    @Test func withoutConfirmationNothingRuns() async throws {
        let runner = ScriptedCommandRunner { _ in ScriptedCommandRunner.result() }

        let result = try await cleaner(runner).run(ifConfirmed: false)

        #expect(result == nil)
        #expect(runner.calls.isEmpty)
    }

    @Test func confirmedRunsExactlyTheDeleteThroughXcrunAndMeasuresFreedSpace() async throws {
        let runner = ScriptedCommandRunner { _ in ScriptedCommandRunner.result(stdout: "", stderr: "") }

        let outcome = try await cleaner(runner, freeSpace: [10_000_000, 14_500_000]).run(ifConfirmed: true)

        let result = try #require(outcome)
        let call = try #require(runner.calls.first)
        #expect(runner.calls.count == 1)
        #expect(call.executable == Self.xcrun)
        #expect(call.arguments == ["simctl", "delete", "unavailable"])
        #expect(call.timeout == .seconds(600))
        #expect(result.succeeded)
        #expect(result.output.isEmpty)
        #expect(result.freedBytes == 4_500_000)
        #expect(result.reportedBytes == nil)
    }

    @Test func aFailedDeleteReportsExitCodeAndOutput() async throws {
        let runner = ScriptedCommandRunner { _ in
            ScriptedCommandRunner.result(exitCode: 1, stderr: "An error was encountered processing the command")
        }

        let outcome = try await cleaner(runner, freeSpace: [5, 5]).run(ifConfirmed: true)

        let result = try #require(outcome)
        #expect(!result.succeeded && result.exitCode == 1)
        #expect(result.output == "An error was encountered processing the command")
        #expect(result.freedBytes == 0)
    }

    @Test func aBinaryThatCannotStartThrows() async {
        let runner = ScriptedCommandRunner { _ in throw ScriptedCommandRunner.StartFailure() }

        await #expect(throws: ScriptedCommandRunner.StartFailure.self) {
            _ = try await cleaner(runner).run(ifConfirmed: true)
        }
    }

    @Test func buildingFromAnEnvironmentNeedsXcode() throws {
        let home = try FakeHome()
        defer { home.remove() }

        #expect(SimulatorCleaner(environment: home.environment(xcrun: Self.xcrun, developerToolsInstalled: false)) == nil)
        #expect(SimulatorCleaner(environment: home.environment(xcrun: nil, developerToolsInstalled: true)) == nil)
        let built = try #require(
            SimulatorCleaner(environment: home.environment(xcrun: Self.xcrun, developerToolsInstalled: true))
        )
        #expect(built.xcrun == Self.xcrun)
    }
}
