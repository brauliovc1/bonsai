import CleanCore
import Foundation

/// A `CommandRunner` that answers from a script and records every call, so tests can check exactly which
/// commands would have run without starting docker or xcrun.
public final class ScriptedCommandRunner: @unchecked Sendable {
    public struct Call: Sendable, Equatable {
        public var executable: URL
        public var arguments: [String]
        public var timeout: Duration
    }

    /// The process could not be started (what `ProcessRunner` throws for a missing executable).
    public struct StartFailure: Error {
        public init() {}
    }

    public typealias Handler = @Sendable (Call) throws -> ProcessResult

    private let lock = NSLock()
    private var recorded: [Call] = []
    private let handler: Handler

    public init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    /// The runner to hand to the code under test.
    public var runner: CommandRunner {
        CommandRunner { [self] executable, arguments, timeout in
            let call = Call(executable: executable, arguments: arguments, timeout: timeout)
            lock.withLock { recorded.append(call) }
            return try handler(call)
        }
    }

    public var calls: [Call] {
        lock.withLock { recorded }
    }

    public static func result(
        exitCode: Int32 = 0,
        stdout: String = "",
        stderr: String = "",
        timedOut: Bool = false
    ) -> ProcessResult {
        ProcessResult(exitCode: exitCode, stdout: Data(stdout.utf8), stderr: stderr, timedOut: timedOut)
    }
}
