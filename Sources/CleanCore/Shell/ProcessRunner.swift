import Foundation

/// Runs external tools. Never through a shell: an absolute executable plus an argument array, so paths
/// with spaces and quotes are passed through untouched.
public enum ProcessRunner {
    /// Added to every child's environment (on top of the inherited one).
    public static let addedEnvironment: [String: String] = [
        "LC_ALL": "C",
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_OPTIONAL_LOCKS": "0",
    ]

    /// How long a process gets to exit after SIGTERM before it is sent SIGKILL.
    static let killGracePeriod: Duration = .seconds(2)

    /// The clock every timeout runs on. It doesn't count time the Mac sleeps: a `git worktree remove` that
    /// is running when the lid closes must not be stopped on wake for the hours the Mac slept.
    public static let timeoutClock = SuspendingClock()

    /// Runs `executable` and waits for it. stdout and stderr are read concurrently, each on a thread of its own
    /// (`PipeReader`), so a child that fills one pipe cannot deadlock, however busy GCD's global queues and the
    /// cooperative pool are. On timeout the child gets SIGTERM, then SIGKILL after 2 s, and the result
    /// has `timedOut == true`. Cancelling the calling task terminates the child.
    ///
    /// Throws only when the process cannot be started; a non-zero exit is a normal result.
    ///
    /// `removingInherited`: inherited variables whose names start with one of these prefixes are dropped
    /// before `addedEnvironment` and `environmentAdditions` are applied. `inheritedEnvironment` replaces
    /// this process's environment as the inherited one (tests).
    public static func run(
        executable: URL,
        arguments: [String],
        directory: URL? = nil,
        environmentAdditions: [String: String] = [:],
        removingInherited prefixes: [String] = [],
        inheritedEnvironment: [String: String]? = nil,
        timeout: Duration = .seconds(60)
    ) async throws -> ProcessResult {
        try await run(
            executable: executable, arguments: arguments, directory: directory,
            environmentAdditions: environmentAdditions, removingInherited: prefixes,
            inheritedEnvironment: inheritedEnvironment, timeout: timeout, clock: timeoutClock
        )
    }

    /// `run` with the timeout measured on `clock` (tests pass one that never advances).
    static func run<C: Clock>(
        executable: URL,
        arguments: [String],
        directory: URL? = nil,
        environmentAdditions: [String: String] = [:],
        removingInherited prefixes: [String] = [],
        inheritedEnvironment: [String: String]? = nil,
        timeout: Duration,
        clock: C
    ) async throws -> ProcessResult where C.Duration == Duration {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let directory {
            process.currentDirectoryURL = directory
        }
        process.environment = (inheritedEnvironment ?? ProcessInfo.processInfo.environment)
            .filter { name, _ in !prefixes.contains { name.hasPrefix($0) } }
            .merging(addedEnvironment) { _, added in added }
            .merging(environmentAdditions) { _, added in added }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        let (exits, exitContinuation) = AsyncStream.makeStream(of: Int32.self)
        process.terminationHandler = { finished in
            exitContinuation.yield(finished.terminationStatus)
            exitContinuation.finish()
        }

        try process.run()
        let child = ChildProcess(process)
        // Both pipes are drained from here on, before this task waits for anything.
        let name = "ProcessRunner \(executable.lastPathComponent)"
        let stdout = PipeReader(stdoutPipe.fileHandleForReading, name: "\(name) stdout")
        let stderr = PipeReader(stderrPipe.fileHandleForReading, name: "\(name) stderr")

        return await withTaskCancellationHandler {
            let watchdog = Task {
                do {
                    try await clock.sleep(for: timeout)
                } catch {
                    return false
                }
                guard child.isRunning else { return false }
                child.terminate()
                try? await clock.sleep(for: killGracePeriod)
                if child.isRunning { child.kill() }
                return true
            }

            var exitCode: Int32 = -1
            for await status in exits {
                exitCode = status
            }
            watchdog.cancel()
            let timedOut = await watchdog.value

            return ProcessResult(
                exitCode: exitCode,
                stdout: await stdout.data(),
                stderr: String(decoding: await stderr.data(), as: UTF8.self),
                timedOut: timedOut
            )
        } onCancel: {
            child.terminate()
        }
    }
}

/// A started `Process`, shared with the watchdog and the cancellation handler. Only the thread-safe parts
/// of `Process` are used after launch.
private final class ChildProcess: @unchecked Sendable {
    private let process: Process

    init(_ process: Process) {
        self.process = process
    }

    var isRunning: Bool { process.isRunning }

    func terminate() {
        if process.isRunning { process.terminate() }
    }

    func kill() {
        if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
    }
}
