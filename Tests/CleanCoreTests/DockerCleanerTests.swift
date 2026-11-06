@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("DockerCleaner")
struct DockerCleanerTests {
    private static let docker = URL(fileURLWithPath: "/opt/homebrew/bin/docker")

    @Test func pruneArgumentsAreExactlySystemPruneF() {
        #expect(DockerCleaner.pruneArguments == ["system", "prune", "-f"])
        #expect(!DockerCleaner.pruneArguments.contains("-a"))
        #expect(!DockerCleaner.pruneArguments.contains("--volumes"))
    }

    @Test func commandLineNamesTheBinaryAndTheArguments() {
        let cleaner = DockerCleaner(docker: Self.docker, freeSpace: ScriptedFreeSpace([nil]).probe)
        #expect(cleaner.commandLine == "/opt/homebrew/bin/docker system prune -f")
    }

    @Test func runsExactlyThePruneAndMeasuresFreedSpace() async throws {
        let runner = ScriptedCommandRunner { _ in
            ScriptedCommandRunner.result(
                stdout: "Deleted Containers:\nabc\n\nTotal reclaimed space: 1.2GB\n",
                stderr: "a note\n"
            )
        }
        let space = ScriptedFreeSpace([1_000, 251_000])
        let cleaner = DockerCleaner(docker: Self.docker, runner: runner.runner, freeSpace: space.probe)

        let result = try await cleaner.run()

        #expect(runner.calls.count == 1)
        #expect(runner.calls[0].executable == Self.docker)
        #expect(runner.calls[0].arguments == ["system", "prune", "-f"])
        #expect(runner.calls[0].timeout == .seconds(900))
        #expect(result.exitCode == 0 && result.succeeded && !result.timedOut)
        #expect(result.freedBytes == 250_000)
        #expect(result.reportedBytes == 1_200_000_000)
        #expect(result.output == "Deleted Containers:\nabc\n\nTotal reclaimed space: 1.2GB\na note")
    }

    @Test func freedSpaceIsNeverNegativeAndNilWhenTheVolumeIsUnreadable() async throws {
        let ok = ScriptedCommandRunner { _ in ScriptedCommandRunner.result() }

        let shrunk = DockerCleaner(docker: Self.docker, runner: ok.runner, freeSpace: ScriptedFreeSpace([500, 100]).probe)
        #expect(try await shrunk.run().freedBytes == 0)

        let unreadable = DockerCleaner(docker: Self.docker, runner: ok.runner, freeSpace: ScriptedFreeSpace([nil]).probe)
        #expect(try await unreadable.run().freedBytes == nil)

        let halfReadable = DockerCleaner(docker: Self.docker, runner: ok.runner, freeSpace: ScriptedFreeSpace([100, nil]).probe)
        #expect(try await halfReadable.run().freedBytes == nil)
    }

    @Test func aFailedPruneReportsExitCodeAndOutput() async throws {
        let runner = ScriptedCommandRunner { _ in
            ScriptedCommandRunner.result(exitCode: 1, stderr: "Cannot connect to the Docker daemon")
        }
        let cleaner = DockerCleaner(docker: Self.docker, runner: runner.runner, freeSpace: ScriptedFreeSpace([1]).probe)

        let result = try await cleaner.run()

        #expect(result.exitCode == 1 && !result.succeeded)
        #expect(result.output == "Cannot connect to the Docker daemon")
        #expect(result.reportedBytes == nil)
    }

    @Test func aTimedOutPruneIsNotASuccess() async throws {
        let runner = ScriptedCommandRunner { _ in ScriptedCommandRunner.result(exitCode: 0, timedOut: true) }
        let cleaner = DockerCleaner(docker: Self.docker, runner: runner.runner, freeSpace: ScriptedFreeSpace([1]).probe)

        let result = try await cleaner.run()

        #expect(result.timedOut && !result.succeeded)
    }

    @Test func aBinaryThatCannotStartThrows() async {
        let runner = ScriptedCommandRunner { _ in throw ScriptedCommandRunner.StartFailure() }
        let cleaner = DockerCleaner(docker: Self.docker, runner: runner.runner, freeSpace: ScriptedFreeSpace([1]).probe)

        await #expect(throws: ScriptedCommandRunner.StartFailure.self) {
            _ = try await cleaner.run()
        }
    }

    @Test func buildingFromAnEnvironmentNeedsDocker() throws {
        let home = try FakeHome()
        defer { home.remove() }

        #expect(DockerCleaner(environment: home.environment(docker: nil)) == nil)
        let cleaner = try #require(DockerCleaner(environment: home.environment(docker: Self.docker)))
        #expect(cleaner.docker == Self.docker)
    }
}
