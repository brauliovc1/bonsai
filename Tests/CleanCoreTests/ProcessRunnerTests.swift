import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("ProcessRunner and Git")
struct ProcessRunnerTests {
    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    @Test func largeStdoutDoesNotDeadlock() async throws {
        let result = try await ProcessRunner.run(
            executable: url("/usr/bin/head"),
            arguments: ["-c", "5000000", "/dev/zero"]
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout.count == 5_000_000)
        #expect(!result.timedOut)
    }

    /// The child is stopped by the timeout and the call returns: it ends by SIGTERM (not by exiting on its own), long
    /// before the 120 s it would sleep. The bound is generous, so a loaded machine or a slow CI runner can't fail it.
    @Test func timeoutTerminates() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let result = try await ProcessRunner.run(
            executable: url("/bin/sleep"),
            arguments: ["120"],
            timeout: .milliseconds(500)
        )
        #expect(result.timedOut)
        #expect(!result.succeeded)
        #expect(result.exitCode == SIGTERM, "ended by the timeout's SIGTERM: \(result.exitCode)")
        #expect(start.duration(to: clock.now) < .seconds(60), "returned long before the child's own exit")
    }

    /// A child that ignores SIGTERM gets SIGKILL after the grace period: it ends by SIGKILL, no sooner than the grace
    /// period, and long before the 120 s it would sleep.
    @Test func timeoutEscalatesToSIGKILL() async throws {
        // A process that ignores SIGTERM (test-only use of sh; ProcessRunner itself never runs a shell).
        let clock = ContinuousClock()
        let start = clock.now
        let result = try await ProcessRunner.run(
            executable: url("/bin/sh"),
            arguments: ["-c", "trap '' TERM; exec /bin/sleep 120"],
            timeout: .milliseconds(300)
        )
        let elapsed = start.duration(to: clock.now)
        #expect(result.timedOut)
        #expect(result.exitCode == SIGKILL, "escalated to SIGKILL: \(result.exitCode)")
        #expect(elapsed >= .seconds(2), "SIGTERM had its grace period first")
        #expect(elapsed < .seconds(60), "returned long before the child's own exit")
    }

    @Test func stderrCaptured() async throws {
        let result = try await ProcessRunner.run(
            executable: url("/bin/ls"),
            arguments: ["/nonexistent-bonsai-path"]
        )
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("No such file or directory"))
        #expect(result.stdout.isEmpty)
    }

    @Test func pathsWithSpacesAndQuotesPassedVerbatim() async throws {
        let argument = #"a "quoted" path with spaces; $HOME `x`"#
        let result = try await ProcessRunner.run(executable: url("/bin/echo"), arguments: [argument])
        #expect(result.stdoutString == argument + "\n")
    }

    @Test func addsEnvironmentAndWorkingDirectory() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let result = try await ProcessRunner.run(
            executable: url("/usr/bin/env"),
            arguments: [],
            directory: directory.url,
            environmentAdditions: ["BONSAI_TEST_VAR": "yes"]
        )
        let lines = Set(result.stdoutString.split(separator: "\n").map(String.init))
        #expect(lines.contains("LC_ALL=C"))
        #expect(lines.contains("GIT_TERMINAL_PROMPT=0"))
        #expect(lines.contains("GIT_OPTIONAL_LOCKS=0"))
        #expect(lines.contains("BONSAI_TEST_VAR=yes"))
        #expect(lines.contains { $0.hasPrefix("PATH=") }, "inherits the parent environment")

        let pwd = try await ProcessRunner.run(executable: url("/bin/pwd"), arguments: ["-P"], directory: directory.url)
        #expect(pwd.stdoutString.trimmingCharacters(in: .newlines) == CanonicalPath.resolve(directory.url))
    }

    @Test func missingExecutableThrows() async {
        await #expect(throws: (any Error).self) {
            try await ProcessRunner.run(executable: url("/nonexistent/tool"), arguments: [])
        }
    }

    @Test func gitHelperThrowsWithExitCodeAndStderr() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let notARepo = fixture.url.appending(path: "plain")
        try FileManager.default.createDirectory(at: notARepo, withIntermediateDirectories: true)

        do {
            try await fixture.git.git(["rev-parse", "--verify", "HEAD"], in: notARepo)
            Issue.record("expected GitError")
        } catch let error as GitError {
            #expect(error.exitCode == 128)
            #expect(error.stderr.contains("not a git repository"))
            #expect(error.arguments == ["rev-parse", "--verify", "HEAD"])
            #expect(!error.timedOut)
        }
    }

    @Test func gitHelperReturnsStdout() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let repo = try await fixture.makeRepo("solo")
        #expect(try await fixture.git.gitString(["rev-parse", "--abbrev-ref", "HEAD"], in: repo) == "main")
        #expect(try await fixture.git.gitString(["log", "-1", "--format=%an <%ae>"], in: repo)
            == "Fixture <fixture@example.invalid>")
        #expect(try await fixture.git.gitString(["rev-parse", "origin/main"], in: repo)
            == fixture.git.gitString(["rev-parse", "HEAD"], in: repo))
        // The scan gives `git --version` 10 s; here it may take as long as the machine needs.
        let version = try await fixture.git.version(timeout: TestWait.limit)
        #expect(version?.isSupported == true)
    }
}
