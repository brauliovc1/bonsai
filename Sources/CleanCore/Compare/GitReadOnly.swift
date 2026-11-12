import Foundation

/// The only process boundary for Compare. Commands use a disposable metadata view: repository config,
/// hooks, attributes drivers and inherited Git settings cannot execute helpers or redirect writes.
public final class GitReadOnly: Sendable {
    public let repository: URL
    public let gitDirectory: URL
    public let commonDirectory: URL
    public let executable: URL
    public let timeout: Duration
    let temporary: URL
    let metadata: URL

    public init(repository: URL, executable: URL, timeout: Duration = .seconds(60)) throws {
        self.executable = executable
        self.timeout = timeout
        let location = try CompareGitView.locate(repository)
        self.repository = location.root
        gitDirectory = location.git
        commonDirectory = location.common
        temporary = FileManager.default.temporaryDirectory.appending(path: "bonsai-compare-\(UUID().uuidString)")
        metadata = temporary.appending(path: "git")
        do { try CompareGitView.make(at: metadata, location: location) }
        catch { try? FileManager.default.removeItem(at: temporary); throw error }
    }

    deinit { try? FileManager.default.removeItem(at: temporary) }

    public static let allowedSubcommands: Set<String> = [
        "rev-parse", "for-each-ref", "symbolic-ref", "merge-base", "rev-list", "log", "diff", "show",
        "cat-file", "ls-files", "status", "worktree", "merge-tree",
    ]

    /// A narrow flag allowlist matters too: even `diff --output` can write a user file.
    public static func permits(_ arguments: [String]) -> Bool {
        guard let command = arguments.first, allowedSubcommands.contains(command) else { return false }
        if command == "worktree" { return arguments == ["worktree", "list", "--porcelain", "-z"] }
        if command == "symbolic-ref" {
            let names = arguments.dropFirst().filter { !$0.hasPrefix("-") }
            guard names.count == 1, names[0].hasPrefix("refs/") || names[0] == "HEAD" else { return false }
        }
        let flags: [String: Set<String>] = [
            "rev-parse": ["--verify", "--end-of-options", "--git-dir", "--git-common-dir", "--show-toplevel"],
            "for-each-ref": ["--sort=-committerdate", "--sort=refname"],
            "symbolic-ref": ["--quiet", "--short"],
            "merge-base": ["--fork-point", "--is-ancestor"],
            "rev-list": ["--left-right", "--count", "--reverse", "--topo-order", "--ancestry-path", "--merges"],
            "log": ["--date=raw", "-g", "--reverse", "--topo-order", "--date-order", "--first-parent", "--merges", "--ancestry-path"],
            "diff": ["--binary", "--no-index", "--numstat", "--name-status", "--name-only", "--raw", "-z", "-M", "-C", "--find-copies-harder", "--no-ext-diff",
                     "--no-textconv", "--no-color", "--ignore-submodules=all", "--ignore-submodules=none", "--submodule=short", "--ignore-all-space", "--full-index"],
            "show": ["--no-ext-diff", "--no-textconv", "--no-color", "--format=", "--numstat", "--name-status", "-z", "-M"],
            "cat-file": ["-s", "-p", "-t"],
            "ls-files": ["--others", "--exclude-standard", "-z", "--stage", "--cached"],
            "status": ["--porcelain=v1", "-z", "--untracked-files=all", "--ignore-submodules=all"],
            "merge-tree": ["--write-tree", "--name-only", "--messages", "-z"],
        ]
        var paths = false
        for arg in arguments.dropFirst() {
            if arg == "--" { paths = true; continue }
            if paths { continue }
            guard !arg.contains("\0") else { return false }
            if arg.hasPrefix("-") {
                if flags[command, default: []].contains(arg) { continue }
                if ["log", "rev-list"].contains(command), arg.hasPrefix("--max-count="),
                   let count = Int(arg.dropFirst(12)), (0...100_000).contains(count) { continue }
                if ["log", "for-each-ref", "show"].contains(command), arg.hasPrefix("--format=") { continue }
                if ["diff", "show"].contains(command), arg.hasPrefix("--unified="), Int(arg.dropFirst(10)) != nil { continue }
                return false
            }
        }
        return true
    }

    public func result(_ arguments: [String]) async throws -> ProcessResult {
        guard Self.permits(arguments) else { throw CompareError("This Git command is outside Compare's read-only allowlist.") }
        try Task.checkCancellation()
        // `worktree list` cannot execute helpers, and needs the real common dir to report registrations.
        let directory = arguments.first == "worktree" ? gitDirectory : metadata
        let safety = ["diff", "show", "log"].contains(arguments.first ?? "") ? ["--no-ext-diff", "--no-textconv"] : []
        let safeArguments = [arguments[0]] + safety + Array(arguments.dropFirst())
        let args = ["--no-pager", "--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "-c", "core.precomposeunicode=true",
                    "--git-dir=\(directory.path)", "--work-tree=\(repository.path)"] + safeArguments
        let result = try await ProcessRunner.run(
            executable: executable, arguments: args, directory: repository,
            environmentAdditions: ["GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_SYSTEM": "/dev/null",
                "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_OPTIONAL_LOCKS": "0", "GIT_NO_REPLACE_OBJECTS": "1",
                "GIT_ATTR_NOSYSTEM": "1", "GIT_LITERAL_PATHSPECS": "1",
                "GIT_OBJECT_DIRECTORY": metadata.appending(path: "objects").path,
                "GIT_ALTERNATE_OBJECT_DIRECTORIES": CompareGitView.quotedAlternate(commonDirectory.appending(path: "objects").path)],
            removingInherited: ["GIT_"], timeout: timeout
        )
        // ProcessRunner terminates a cancelled child but returns its exit result.
        try Task.checkCancellation()
        return result
    }

    public func data(_ arguments: [String]) async throws -> Data {
        let result = try await result(arguments)
        guard result.succeeded else {
            throw CompareError(result.timedOut ? "Git took too long. Refresh to try again." : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.stdout
    }

    public func string(_ arguments: [String]) async throws -> String {
        String(decoding: try await data(arguments), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func resolve(_ ref: String) async throws -> String {
        try await string(["rev-parse", "--verify", "--end-of-options", ref + "^{commit}"])
    }
}

public struct CompareError: Error, Sendable, CustomStringConvertible {
    public var description: String
    public init(_ description: String) { self.description = description }
}
