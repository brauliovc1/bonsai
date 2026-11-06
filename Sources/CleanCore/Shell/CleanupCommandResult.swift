import Foundation

/// What a cleanup command (`docker system prune -f`, `xcrun simctl delete unavailable`) did.
public struct CleanupCommandResult: Sendable, Equatable {
    public var exitCode: Int32
    /// stdout, then stderr when it has something to say.
    public var output: String
    public var timedOut: Bool
    /// Free space on the home volume after minus before, never negative. nil when the volume could not be
    /// read. Docker Desktop shrinks `Docker.raw` some time after a prune, so this can be ~0 right after
    /// a prune that freed gigabytes inside the VM.
    public var freedBytes: Int64?
    /// The number the tool printed itself (docker's "Total reclaimed space"), when it prints one.
    public var reportedBytes: Int64?

    public init(
        exitCode: Int32,
        output: String,
        timedOut: Bool = false,
        freedBytes: Int64? = nil,
        reportedBytes: Int64? = nil
    ) {
        self.exitCode = exitCode
        self.output = output
        self.timedOut = timedOut
        self.freedBytes = freedBytes
        self.reportedBytes = reportedBytes
    }

    public var succeeded: Bool { exitCode == 0 && !timedOut }

    /// Runs one cleanup command and measures free space around it.
    static func measuredRun(
        executable: URL,
        arguments: [String],
        timeout: Duration,
        runner: CommandRunner,
        freeSpace: FreeSpaceProbe,
        reportedBytes: (String) -> Int64? = { _ in nil }
    ) async throws -> CleanupCommandResult {
        let before = freeSpace.availableBytes()
        let result = try await runner.run(executable, arguments, timeout: timeout)
        let after = freeSpace.availableBytes()

        var freed: Int64?
        if let before, let after {
            freed = max(0, after - before)
        }
        let stdout = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        return CleanupCommandResult(
            exitCode: result.exitCode,
            output: output,
            timedOut: result.timedOut,
            freedBytes: freed,
            reportedBytes: reportedBytes(output)
        )
    }
}
