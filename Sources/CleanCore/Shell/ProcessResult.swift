import Foundation

/// What a finished (or timed-out) child process left behind.
public struct ProcessResult: Sendable {
    public var exitCode: Int32
    public var stdout: Data
    public var stderr: String
    public var timedOut: Bool

    public init(exitCode: Int32, stdout: Data, stderr: String, timedOut: Bool) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }

    /// Exited with status 0 and was not stopped by the timeout.
    public var succeeded: Bool { exitCode == 0 && !timedOut }

    /// stdout decoded as UTF-8 (invalid bytes replaced).
    public var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
}
