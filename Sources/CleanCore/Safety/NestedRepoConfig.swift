import Foundation

/// A nested repo's own config, read with `git config --file <file> --list -z`, which only reads the file:
/// it follows no includes and runs nothing. Read before any other git command runs in that repo
/// (PLAN §4.1 "Nested checkouts").
struct NestedRepoConfig: Sendable {
    /// Keys as git lists them (section and name lowercased, subsection as written), with their values.
    var entries: [(key: String, value: String)]

    /// Reads `config` and, when present, `config.worktree` in `gitDir`. nil when a file can't be read.
    /// git runs in `/`, so it doesn't even discover the repo.
    static func read(gitDir: URL, git: Git) async -> NestedRepoConfig? {
        var entries: [(key: String, value: String)] = []
        for name in ["config", "config.worktree"] {
            let file = gitDir.appending(path: name)
            if name == "config.worktree", PathPresence.of(file.path) == .missing { continue }
            guard let result = try? await git.result(["config", "--file", file.path, "--list", "-z"], in: URL(fileURLWithPath: "/")),
                  result.succeeded
            else { return nil }
            entries += parse(result.stdout)
        }
        return NestedRepoConfig(entries: entries)
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
