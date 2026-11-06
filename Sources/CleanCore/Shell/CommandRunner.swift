import Foundation

/// How the Docker and Simulator code starts external commands. Production code uses `.live`, which is
/// `ProcessRunner`; tests pass a scripted runner, so no test ever starts docker or xcrun.
public struct CommandRunner: Sendable {
    public typealias Handler = @Sendable (
        _ executable: URL,
        _ arguments: [String],
        _ timeout: Duration
    ) async throws -> ProcessResult

    private let handler: Handler

    public init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    /// Runs `executable` with an argument array (never through a shell). Throws only when the process
    /// cannot be started; a non-zero exit or a timeout is a normal result.
    public func run(_ executable: URL, _ arguments: [String], timeout: Duration) async throws -> ProcessResult {
        try await handler(executable, arguments, timeout)
    }

    public static let live = CommandRunner { executable, arguments, timeout in
        try await ProcessRunner.run(executable: executable, arguments: arguments, timeout: timeout)
    }
}
