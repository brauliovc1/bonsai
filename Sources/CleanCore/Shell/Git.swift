import Foundation

/// Runs git through `ProcessRunner`.
public struct Git: Sendable {
    public var executable: URL
    /// Extra environment for every call (the test fixture uses this to isolate git from the user's config).
    public var environmentAdditions: [String: String]
    /// Arguments placed before the subcommand, e.g. `-c key=value` pairs.
    public var leadingArguments: [String]
    public var timeout: Duration
    /// Test seam: the environment git inherits (nil = this process's), before `GIT_*` is stripped.
    var inheritedEnvironment: [String: String]?

    /// Before every subcommand: git never runs an fsmonitor hook, whatever a repo's config names.
    public static let fixedArguments = ["-c", "core.fsmonitor=false"]

    /// Inherited variables with this prefix never reach git: `GIT_DIR`, `GIT_INDEX_FILE`, `GIT_WORK_TREE`,
    /// `GIT_CEILING_DIRECTORIES` and the like would make it answer about something else. The ones
    /// Bonsai sets itself (`ProcessRunner.addedEnvironment`, `environmentAdditions`) are added after.
    public static let strippedEnvironmentPrefix = "GIT_"

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
        let result = try await run(arguments: leadingArguments + ["-C", directory.path] + args, timeout: timeout)
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
        try await run(arguments: leadingArguments + ["-C", directory.path] + args, timeout: timeout)
    }

    /// Every git process starts here: `fixedArguments` first, inherited `GIT_*` variables removed.
    private func run(arguments: [String], timeout: Duration) async throws -> ProcessResult {
        try await ProcessRunner.run(
            executable: executable,
            arguments: Self.fixedArguments + arguments,
            environmentAdditions: environmentAdditions,
            removingInherited: [Self.strippedEnvironmentPrefix],
            inheritedEnvironment: inheritedEnvironment,
            timeout: timeout
        )
    }

    /// Options to put before a git subcommand that creates something at `path` (`worktree add`).
    ///
    /// Foundation's `Process` hands arguments to the child decomposed (NFD): git receives "é" as "e" + U+0301
    /// whatever string is passed. This sets `core.precomposeunicode` for the one call so git turns the
    /// argument back into the form `path` has: composed when `path` is composed (what git registers on
    /// macOS), left decomposed otherwise. git can't recompose a path that contains an emoji; it then keeps the
    /// decomposed form, which still names the same folder on APFS. ASCII paths need nothing. To *match* an
    /// existing registration, run git inside the folder instead (`Remover.removeCommand`).
    public static func unicodeOptions(forPath path: String) -> [String] {
        guard path.utf8.contains(where: { $0 >= 0x80 }) else { return [] }
        let composed = path.precomposedStringWithCanonicalMapping.utf8.elementsEqual(path.utf8)
        return ["-c", "core.precomposeunicode=\(composed)"]
    }

    /// Like `git(_:in:)`, decoded as UTF-8 with surrounding whitespace trimmed.
    public func gitString(_ args: [String], in directory: URL) async throws -> String {
        let data = try await git(args, in: directory)
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The installed git's version (`git --version`), given at most `timeout`.
    public func version(timeout: Duration = .seconds(10)) async throws -> GitVersion? {
        let result = try await run(arguments: ["--version"], timeout: timeout)
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
