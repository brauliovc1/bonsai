@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// `docker system prune -f` and `xcrun simctl delete unavailable` log themselves inside CleanCore once they
/// ran (wave-2 review item D), through `RemovalLog.append`.
@Suite("Cleanup command logging")
struct CleanupLoggingTests {
    private static let docker = URL(fileURLWithPath: "/fake/bin/docker")
    private static let xcrun = URL(fileURLWithPath: "/fake/bin/xcrun")
    private static let desktop = DockerReport(
        state: .running,
        daemonOperatingSystem: "Docker Desktop",
        usage: [
            DockerUsageRow(type: "Images", total: 3, active: 1, sizeBytes: 9_000, reclaimableBytes: 5_000),
            DockerUsageRow(type: "Local Volumes", total: 1, active: 0, sizeBytes: 2_000, reclaimableBytes: 2_000),
        ]
    )
    private static let date = Date(timeIntervalSince1970: 1_800_000_000)

    private let folder: TemporaryDirectory

    init() throws {
        folder = try TemporaryDirectory(prefix: "clean-claude-cleanup-log")
    }

    private var log: RemovalLog { RemovalLog(directory: folder.url) }

    private func docker(_ runner: ScriptedCommandRunner, freeSpace: [Int64?] = [1_000, 4_000], log: RemovalLog? = nil) -> DockerCleaner {
        DockerCleaner(
            docker: Self.docker,
            runner: runner.runner,
            freeSpace: ScriptedFreeSpace(freeSpace).probe,
            log: log ?? self.log,
            now: { Self.date }
        )
    }

    private func simulators(_ runner: ScriptedCommandRunner, freeSpace: [Int64?] = [1_000, 4_000]) -> SimulatorCleaner {
        SimulatorCleaner(xcrun: Self.xcrun, runner: runner.runner, freeSpace: ScriptedFreeSpace(freeSpace).probe, log: log, now: { Self.date })
    }

    @Test func aPruneThatRanIsLoggedWithTheCommandAndTheMeasuredBytes() async throws {
        let runner = ScriptedCommandRunner { _ in ScriptedCommandRunner.result(stdout: "Total reclaimed space: 1.5kB\n") }

        let result = try #require(try await docker(runner).run(ifConfirmed: true, report: Self.desktop))

        let entries = try log.entries()
        let entry = try #require(entries.first)
        #expect(entries.count == 1 && result.logEntry == entry && result.logged && result.logError == nil)
        #expect(entry.action == .dockerPrune && entry.mode == .manual && !entry.isRestorable)
        #expect(entry.date == Self.date)
        #expect(entry.path == "/fake/bin/docker")
        #expect(entry.estimatedBytes == 5_000, "the prune ceiling: reclaimable minus volumes")
        #expect(entry.freedBytes == 3_000)
        #expect(entry.notes == ["/fake/bin/docker system prune -f", "the tool reported 1.5 KB reclaimed"])
    }

    @Test func aFailedOrTimedOutPruneIsLoggedWithHowItEnded() async throws {
        let failed = ScriptedCommandRunner { _ in ScriptedCommandRunner.result(exitCode: 1, stderr: "daemon error") }
        _ = try await docker(failed).run(ifConfirmed: true, report: Self.desktop)
        let timedOut = ScriptedCommandRunner { _ in ScriptedCommandRunner.result(timedOut: true) }
        _ = try await docker(timedOut).run(ifConfirmed: true, report: Self.desktop)

        #expect(try log.entries().map(\.notes) == [
            ["/fake/bin/docker system prune -f", "exit 1"],
            ["/fake/bin/docker system prune -f", "timed out"],
        ])
    }

    @Test func aPruneThatDidNotRunIsNotLogged() async throws {
        let runner = ScriptedCommandRunner { _ in ScriptedCommandRunner.result() }
        #expect(try await docker(runner).run(ifConfirmed: false, report: Self.desktop) == nil)
        await #expect(throws: DockerCleaner.Refused.self) {
            _ = try await docker(runner).run(ifConfirmed: true, report: DockerReport(state: .notRunning))
        }
        let unstartable = ScriptedCommandRunner { _ in throw ScriptedCommandRunner.StartFailure() }
        await #expect(throws: ScriptedCommandRunner.StartFailure.self) {
            _ = try await docker(unstartable).run(ifConfirmed: true, report: Self.desktop)
        }
        #expect(runner.calls.isEmpty)
        #expect(try log.entries().isEmpty)
    }

    @Test func aLogThatCannotBeWrittenStillReturnsTheResult() async throws {
        let blocked = folder.url.appending(path: "not-a-folder")
        try Data("x".utf8).write(to: blocked)
        let runner = ScriptedCommandRunner { _ in ScriptedCommandRunner.result() }

        let result = try #require(try await docker(runner, log: RemovalLog(directory: blocked)).run(ifConfirmed: true, report: Self.desktop))

        #expect(runner.calls.count == 1 && result.succeeded)
        #expect(!result.logged && result.logEntry != nil)
        #expect(result.logError?.hasPrefix("the cleanup was not logged") == true)
    }

    @Test func aSimulatorDeleteThatRanIsLogged() async throws {
        let runner = ScriptedCommandRunner { _ in ScriptedCommandRunner.result() }

        let result = try #require(try await simulators(runner).run(ifConfirmed: true, estimatedBytes: 7_000))

        let entry = try #require(try log.entries().first)
        #expect(result.logEntry == entry && result.logged)
        #expect(entry.action == .simulatorsDeleteUnavailable && entry.mode == .manual)
        #expect(entry.estimatedBytes == 7_000 && entry.freedBytes == 3_000)
        #expect(entry.notes == ["/fake/bin/xcrun simctl delete unavailable"])
    }

    @Test func aSimulatorDeleteThatDidNotRunIsNotLogged() async throws {
        let runner = ScriptedCommandRunner { _ in ScriptedCommandRunner.result() }
        #expect(try await simulators(runner).run(ifConfirmed: false) == nil)
        #expect(try log.entries().isEmpty)
    }

    @Test func cleanersFromAnEnvironmentLogIntoItsSettingsFolder() throws {
        let home = try FakeHome()
        defer { home.remove() }
        let environment = home.environment(docker: Self.docker, xcrun: Self.xcrun, developerToolsInstalled: true)
        #expect(try #require(DockerCleaner(environment: environment)).log.directory == environment.settingsDirectory)
        #expect(try #require(SimulatorCleaner(environment: environment)).log.directory == environment.settingsDirectory)
    }

    // Wave-2 review item C: one encoder; the usage report's name is the idle clock's.
    @Test func theTranscriptFolderNameHasOneEncoding() {
        for path in ["/Users/a/my.repo/.claude/worktrees/x_y", "/a/wt \u{1F680} caf\u{E9}", "/a/cafe\u{301}", ""] {
            #expect(ClaudeProjectFolderName.encode(path) == TranscriptFolderEncoding.encode(path), "\(path)")
        }
        #expect(ClaudeProjectFolderName.encode("/a/wt \u{1F680} caf\u{E9}") == "-a-wt----caf-")
    }
}
