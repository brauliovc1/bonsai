import Foundation

/// A nested repo's own config, read with `git config --file <file> --list -z`, which only reads the file:
/// it follows no includes and runs nothing. Read before any other git command runs in that repo
/// (PLAN §4.1 "Nested checkouts").
struct NestedRepoConfig: Sendable {
    /// Keys as git lists them (section and name lowercased, subsection as written), with their values.
    var entries: [(key: String, value: String)]

    /// Why a config file couldn't be read: git's first error line.
    struct Unreadable: Error, Sendable, Hashable {
        var message: String
    }

    /// Reads `config` and, when present, `config.worktree` in `gitDir`; fails when a file can't be read.
    /// git runs in `/`, so it doesn't even discover the repo.
    static func read(gitDir: URL, git: Git) async -> Result<NestedRepoConfig, Unreadable> {
        var entries: [(key: String, value: String)] = []
        for name in ["config", "config.worktree"] {
            let file = gitDir.appending(path: name)
            if name == "config.worktree", PathPresence.of(file.path) == .missing { continue }
            let arguments = ["config", "--file", file.path, "--list", "-z"]
            do {
                let result = try await git.result(arguments, in: URL(fileURLWithPath: "/"))
                guard result.succeeded else {
                    let error = GitError(exitCode: result.exitCode, stderr: result.stderr, arguments: arguments, timedOut: result.timedOut)
                    return .failure(Unreadable(message: NestedCloneCheck.firstLine(of: error)))
                }
                entries += parse(result.stdout)
            } catch {
                return .failure(Unreadable(message: "\(error)"))
            }
        }
        return .success(NestedRepoConfig(entries: entries))
    }

    /// `--list -z` output: `key\nvalue\0` per entry (no `\n` when the key has no value).
    static func parse(_ data: Data) -> [(key: String, value: String)] {
        data.split(separator: 0).map { field in
            let text = String(decoding: field, as: UTF8.self)
            guard let newline = text.firstIndex(of: "\n") else { return (text, "") }
            return (String(text[..<newline]), String(text[text.index(after: newline)...]))
        }
    }

    /// Keys that make git run a command or read another file: a `core.fsmonitor` that is not a boolean
    /// false (Xcode and SwiftPM write `core.fsmonitor=false` into every package checkout and mirror),
    /// `filter.*`, `include.*` and `includeIf.*`.
    var commandKeys: [String] {
        entries.filter { key, value in
            let lowered = key.lowercased()
            if lowered == "core.fsmonitor" { return !Self.isFalse(value) }
            return lowered.hasPrefix("filter.") || lowered.hasPrefix("include.") || lowered.hasPrefix("includeif.")
        }.map(\.key)
    }

    /// A mirror: some remote has `mirror = true` and fetches `+refs/*:refs/*` (how SwiftPM and Xcode keep
    /// their `repositories/` caches). Its refs all come from that remote.
    var isMirror: Bool {
        let mirrored = entries.compactMap { key, value -> String? in
            guard key.hasPrefix("remote."), key.hasSuffix(".mirror"), Self.isTrue(value) else { return nil }
            return String(key.dropFirst("remote.".count).dropLast(".mirror".count))
        }
        return mirrored.contains { name in
            entries.contains { $0.key == "remote.\(name).fetch" && $0.value == "+refs/*:refs/*" }
        }
    }

    private static func isFalse(_ value: String) -> Bool {
        ["false", "no", "off", "0"].contains(value.lowercased())
    }

    private static func isTrue(_ value: String) -> Bool {
        ["true", "yes", "on", "1"].contains(value.lowercased())
    }
}
