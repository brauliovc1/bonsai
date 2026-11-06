import Foundation

/// Runs git through `ProcessRunner`.
public struct Git: Sendable {
    public var executable: URL
    /// Extra environment for every call (the test fixture uses this to isolate git from the user's config).
    public var environmentAdditions: [String: String]
    /// Arguments placed before the subcommand, e.g. `-c key=value` pairs.
    public var leadingArguments: [String]
    public var timeout: Duration

    public init(
        executable: URL,
        environmentAdditions: [String: String] = [:],
        leadingArguments: [String] = [],
        timeout: Duration = .seconds(60)
    ) {
        self.executable = executable
        self.environmentAdditions = environmentAdditions
        self.leadingArguments = leadingArguments
        self.timeout = timeout
    }

    /// Runs `git -C <directory> <args>` and returns stdout. Throws `GitError` on a non-zero exit or timeout.
    @discardableResult
    public func git(_ args: [String], in directory: URL) async throws -> Data {
        let result = try await ProcessRunner.run(
            executable: executable,
            arguments: leadingArguments + ["-C", directory.path] + args,
            environmentAdditions: environmentAdditions,
            timeout: timeout
        )
        guard result.succeeded else {
            throw GitError(
                exitCode: result.exitCode,
                stderr: result.stderr,
                arguments: args,
                timedOut: result.timedOut
            )
        }
        return result.stdout
    }

    /// Runs `git -C <directory> <args>` and returns the whole result; a non-zero exit is not an error here.
    /// For commands that report on stderr (`worktree prune --verbose`) or whose exit code is the answer.
    public func result(_ args: [String], in directory: URL) async throws -> ProcessResult {
        try await ProcessRunner.run(
            executable: executable,
            arguments: leadingArguments + ["-C", directory.path] + args,
            environmentAdditions: environmentAdditions,
            timeout: timeout
        )
    }

    /// Like `git(_:in:)`, decoded as UTF-8 with surrounding whitespace trimmed.
    public func gitString(_ args: [String], in directory: URL) async throws -> String {
        let data = try await git(args, in: directory)
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The installed git's version (`git --version`).
    public func version() async throws -> GitVersion? {
        let result = try await ProcessRunner.run(
            executable: executable,
            arguments: ["--version"],
            environmentAdditions: environmentAdditions,
            timeout: .seconds(10)
        )
        guard result.succeeded else {
            throw GitError(
                exitCode: result.exitCode,
                stderr: result.stderr,
                arguments: ["--version"],
                timedOut: result.timedOut
            )
        }
        return GitVersion(parsing: result.stdoutString)
    }
}
