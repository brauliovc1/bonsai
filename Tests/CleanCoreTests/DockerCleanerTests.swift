@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("DockerCleaner")
struct DockerCleanerTests {
    /// A path that does not exist: even a runner mistake could not start a real docker.
    private static let docker = URL(fileURLWithPath: "/fake/bin/docker")
    private static let desktop = DockerReport(state: .running, daemonOperatingSystem: "Docker Desktop")
    /// Each test's own log folder, removed with the test.
    private let logFolder: TemporaryDirectory

    init() throws {
        logFolder = try TemporaryDirectory(prefix: "bonsai-docker-log")
    }

    private func cleaner(
        _ runner: ScriptedCommandRunner,
        freeSpace: [Int64?] = [1, 1]
    ) -> DockerCleaner {
        DockerCleaner(
            docker: Self.docker,
            runner: runner.runner,
            freeSpace: ScriptedFreeSpace(freeSpace).probe,
            log: RemovalLog(directory: logFolder.url)
        )
    }

    @Test func pruneArgumentsAreExactlySystemPruneF() {
        #expect(DockerCleaner.pruneArguments == ["system", "prune", "-f"])
        #expect(!DockerCleaner.pruneArguments.contains("-a"))
        #expect(!DockerCleaner.pruneArguments.contains("--volumes"))
    }

    @Test func commandLineNamesTheBinaryAndTheArguments() {
        let runner = ScriptedCommandRunner { _ in ScriptedCommandRunner.result() }
        #expect(cleaner(runner).commandLine == "/fake/bin/docker system prune -f")
    }

    // MARK: The --yes gate

    @Test func withoutConfirmationNothingRunsEvenForAHealthyDockerDesktop() async throws {
        let runner = ScriptedCommandRunner { _ in ScriptedCommandRunner.result() }

        let result = try await cleaner(runner).run(ifConfirmed: false, report: Self.desktop)

        #expect(result == nil)
        #expect(runner.calls.isEmpty)
    }

    @Test func withoutConfirmationNothingRunsAndNothingThrowsForABlockedReport() async throws {
        let runner = ScriptedCommandRunner { _ in ScriptedCommandRunner.result() }

        let result = try await cleaner(runner).run(ifConfirmed: false, report: DockerReport(state: .notRunning))

        #expect(result == nil)
        #expect(runner.calls.isEmpty)
    }

    @Test(arguments: [
        DockerReport(state: .notInstalled),
        DockerReport(state: .notRunning, notRunningReason: "docker info did not answer within 5 s"),
        DockerReport(state: .running, daemonOperatingSystem: "Ubuntu 22.04.4 LTS"),
        DockerReport(state: .running, daemonOperatingSystem: "Alpine Linux v3.19"),
        DockerReport(state: .running, daemonOperatingSystem: nil),
    ])
    func confirmedButBlockedRefusesAndRunsNothing(report: DockerReport) async throws {
        let runner = ScriptedCommandRunner { _ in ScriptedCommandRunner.result() }

        await #expect(throws: DockerCleaner.Refused.self) {
            _ = try await cleaner(runner).run(ifConfirmed: true, report: report)
        }
        #expect(runner.calls.isEmpty)
    }

    // MARK: Running

    @Test func confirmedRunsExactlyThePruneAndMeasuresFreedSpace() async throws {
        let runner = ScriptedCommandRunner { _ in
            ScriptedCommandRunner.result(
                stdout: "Deleted Containers:\nabc\n\nTotal reclaimed space: 1.2GB\n",
                stderr: "a note\n"
            )
        }

        let outcome = try await cleaner(runner, freeSpace: [1_000, 251_000]).run(ifConfirmed: true, report: Self.desktop)

        let result = try #require(outcome)
        let call = try #require(runner.calls.first)
        #expect(runner.calls.count == 1)
        #expect(call.executable == Self.docker)
        #expect(call.arguments == ["system", "prune", "-f"])
        #expect(call.timeout == .seconds(900))
        #expect(result.exitCode == 0 && result.succeeded && !result.timedOut)
        #expect(result.freedBytes == 250_000)
        #expect(result.reportedBytes == 1_200_000_000)
        #expect(result.output == "Deleted Containers:\nabc\n\nTotal reclaimed space: 1.2GB\na note")
    }

    @Test func freedSpaceIsNeverNegativeAndNilWhenTheVolumeIsUnreadable() async throws {
        let ok = ScriptedCommandRunner { _ in ScriptedCommandRunner.result() }

        let shrunk = try await cleaner(ok, freeSpace: [500, 100]).run(ifConfirmed: true, report: Self.desktop)
        let shrunkResult = try #require(shrunk)
        #expect(shrunkResult.freedBytes == 0)

        let unreadable = try await cleaner(ok, freeSpace: [nil]).run(ifConfirmed: true, report: Self.desktop)
        let unreadableResult = try #require(unreadable)
        #expect(unreadableResult.freedBytes == nil)

        let halfReadable = try await cleaner(ok, freeSpace: [100, nil]).run(ifConfirmed: true, report: Self.desktop)
        let halfReadableResult = try #require(halfReadable)
        #expect(halfReadableResult.freedBytes == nil)
    }

    @Test func aFailedPruneReportsExitCodeAndOutput() async throws {
        let runner = ScriptedCommandRunner { _ in
            ScriptedCommandRunner.result(exitCode: 1, stderr: "Cannot connect to the Docker daemon")
        }

        let outcome = try await cleaner(runner).run(ifConfirmed: true, report: Self.desktop)

        let result = try #require(outcome)
        #expect(result.exitCode == 1 && !result.succeeded)
        #expect(result.output == "Cannot connect to the Docker daemon")
        #expect(result.reportedBytes == nil)
    }

    @Test func aTimedOutPruneIsNotASuccess() async throws {
        let runner = ScriptedCommandRunner { _ in ScriptedCommandRunner.result(exitCode: 0, timedOut: true) }

        let outcome = try await cleaner(runner).run(ifConfirmed: true, report: Self.desktop)

        let result = try #require(outcome)
        #expect(result.timedOut && !result.succeeded)
    }

    @Test func aBinaryThatCannotStartThrowsItsOwnError() async {
        let runner = ScriptedCommandRunner { _ in throw ScriptedCommandRunner.StartFailure() }

        await #expect(throws: ScriptedCommandRunner.StartFailure.self) {
            _ = try await cleaner(runner).run(ifConfirmed: true, report: Self.desktop)
        }
    }

    @Test func buildingFromAnEnvironmentNeedsDocker() throws {
        let home = try FakeHome()
        defer { home.remove() }

        #expect(DockerCleaner(environment: home.environment(docker: nil)) == nil)
        let built = try #require(DockerCleaner(environment: home.environment(docker: Self.docker)))
        #expect(built.docker == Self.docker)
    }
}
