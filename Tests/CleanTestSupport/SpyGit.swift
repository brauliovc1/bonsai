import CleanCore
import Foundation

/// A git that writes down every argument list it is given, then runs the fixture's git: for tests that must
/// see exactly what was asked of git (one `--force`, never two; git never run inside a package copy).
public struct SpyGit: Sendable {
    /// Use this wherever the code under test takes a `Git`.
    public let git: Git
    public let logFile: URL

    public init(fixture: GitFixture) throws {
        let folder = fixture.url.appending(path: "spy-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        logFile = folder.appending(path: "calls.log")
        let script = folder.appending(path: "git")
        // One printf per call, so calls running at the same time don't interleave: arguments end with US
        // (0x1f), calls with RS (0x1e).
        let text = """
            #!/bin/sh
            line=''
            for argument in "$@"; do line="$line$argument$(printf '\\037')"; done
            printf '%s\\036' "$line" >> '\(logFile.path)'
            exec '\(fixture.git.executable.path)' "$@"

            """
        try Data(text.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        var git = fixture.git
        git.executable = script
        self.git = git
    }

    /// Every call so far, in order: its arguments as git got them (`-c` options first, then `-C <dir>`).
    public func calls() -> [[String]] {
        guard let data = try? Data(contentsOf: logFile) else { return [] }
        return data.split(separator: 0x1e).map { call in
            call.split(separator: 0x1f, omittingEmptySubsequences: false).dropLast().map { String(decoding: $0, as: UTF8.self) }
        }
    }

    /// The calls whose arguments contain `subcommand` in order ("worktree", "remove").
    public func calls(_ subcommand: String...) -> [[String]] {
        calls().filter { call in
            guard let start = call.firstIndex(of: subcommand[0]) else { return false }
            return Array(call[start...].prefix(subcommand.count)) == subcommand
        }
    }

    /// The folders git ran in (`-C`), and every argument that is a path, for "never inside" checks.
    public func touchedPaths() -> [String] {
        calls().flatMap { $0.filter { $0.hasPrefix("/") } }
    }
}
