import Foundation

/// A git command that exited non-zero (or was stopped by its timeout).
public struct GitError: Error, Sendable, Equatable, CustomStringConvertible {
    public var exitCode: Int32
    public var stderr: String
    public var arguments: [String]
    public var timedOut: Bool

    public init(exitCode: Int32, stderr: String, arguments: [String], timedOut: Bool = false) {
        self.exitCode = exitCode
        self.stderr = stderr
        self.arguments = arguments
        self.timedOut = timedOut
    }

    public var description: String {
        let command = (["git"] + arguments).joined(separator: " ")
        if timedOut { return "\(command) timed out" }
        let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(command) failed (exit \(exitCode))" + (message.isEmpty ? "" : ": \(message)")
    }
}
