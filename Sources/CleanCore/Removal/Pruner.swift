import Foundation

/// `git worktree prune` for worktrees whose folders are gone (PLAN §4.1 "Folder missing"). git prunes every
/// prunable entry of a repo at once, so the whole repo is refused when any entry could be work in disguise:
/// a path under `/Volumes/` (an unplugged drive looks the same as a deleted folder) or a detached HEAD that
/// no branch, tag or remote reaches (pruning drops the only record of it).
public struct Pruner: Sendable {
    public var git: Git
    public var log: RemovalLog
    public var now: @Sendable () -> Date

    public init(git: Git, environment: CleanEnvironment) {
        self.git = git
        self.log = RemovalLog(environment: environment)
        self.now = environment.now
    }

    /// One registration git would prune, read from `<common git dir>/worktrees/<name>/` beforehand.
    public struct Entry: Sendable, Hashable {
        public var name: String
        public var reason: String
        /// The worktree folder the registration points at (from its `gitdir` file), when readable.
        public var path: String?
        public var branch: String?
        /// The commit a detached registration is at.
        public var head: String?

        /// One line for the log's notes.
        public var note: String {
            var parts = ["worktrees/\(name): \(reason)"]
            if let path { parts.append("path \(path)") }
            if let branch { parts.append("branch \(branch)") } else if let head { parts.append("detached at \(head)") }
            return parts.joined(separator: "; ")
        }
    }

    public struct Preview: Sendable, Hashable {
        public var repoPath: String
        public var entries: [Entry]
        /// Why this repo's prune is refused; empty when it may go ahead.
        public var refusals: [String]
    }

    public struct Result: Sendable, Hashable {
        public var repoPath: String
        /// `worktrees/<name>: <reason>` per pruned registration.
        public var pruned: [String]
        /// nil when nothing was pruned (nothing is logged then).
        public var entry: RemovalLogEntry?
        public var warnings: [String]
    }

    public struct Refused: Error, Sendable, CustomStringConvertible {
        public var refusals: [String]
        public var description: String { "prune refused: " + refusals.joined(separator: "; ") }
    }

    /// What `prune` would remove (`git worktree prune --dry-run --verbose`), each entry's HEAD and branch,
    /// and whether the repo's prune is refused.
    public func preview(repo: URL) async throws -> Preview {
        let lines = try await run(["worktree", "prune", "--dry-run", "--verbose"], in: repo)
        guard !lines.isEmpty else { return Preview(repoPath: repo.path, entries: [], refusals: []) }
        let commonDir = URL(fileURLWithPath: try await git.gitString(
            ["rev-parse", "--path-format=absolute", "--git-common-dir"],
            in: repo
        ))
        var entries: [Entry] = []
        var refusals: [String] = []
        for line in lines {
            let entry = Self.read(line, commonDir: commonDir)
            entries.append(entry)
            if let path = entry.path, path.hasPrefix("/Volumes/") {
                refusals.append("worktrees/\(entry.name) is on \(path), which may be an unplugged drive")
            }
            if entry.branch == nil, let head = entry.head, try await isUnreachable(head, in: repo) {
                refusals.append("worktrees/\(entry.name) is detached at \(head), which no branch, tag or remote reaches")
            }
        }
        return Preview(repoPath: repo.path, entries: entries, refusals: refusals)
    }

    /// Re-reads the preview, refuses when it has refusals, prunes, then logs one `worktreePrune` entry for
    /// the repo with each pruned entry's path, branch or HEAD in `notes`.
    public func prune(repo: URL, mode: RemovalMode = .manual) async throws -> Result {
        let preview = try await preview(repo: repo)
        guard preview.refusals.isEmpty else { throw Refused(refusals: preview.refusals) }
        let pruned = try await run(["worktree", "prune", "--verbose"], in: repo)
        guard !pruned.isEmpty else { return Result(repoPath: repo.path, pruned: [], entry: nil, warnings: []) }

        let known = Dictionary(preview.entries.map { ("worktrees/\($0.name)", $0) }) { first, _ in first }
        let notes = pruned.map { line in
            let key = String(line.prefix { $0 != ":" })
            return known[key]?.note ?? line + "; not read before pruning"
        }
        let entry = RemovalLogEntry(
            date: now(),
            mode: mode,
            action: .worktreePrune,
            repoPath: repo.path,
            path: repo.path,
            notes: notes
        )
        var warnings: [String] = []
        do {
            try log.append(entry)
        } catch {
            warnings.append("the prune was not logged: \(error)")
        }
        return Result(repoPath: repo.path, pruned: pruned, entry: entry, warnings: warnings)
    }

    /// Reads `worktrees/<name>/HEAD` and `gitdir` for a `worktrees/<name>: <reason>` line.
    static func read(_ line: String, commonDir: URL) -> Entry {
        let label = String(line.prefix { $0 != ":" })
        let reason = line.dropFirst(label.count).drop { $0 == ":" || $0 == " " }
        let name = label.hasPrefix("worktrees/") ? String(label.dropFirst("worktrees/".count)) : label
        let admin = commonDir.appending(path: "worktrees/\(name)", directoryHint: .isDirectory)
        func contents(_ file: String) -> String? {
            (try? String(contentsOf: admin.appending(path: file), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var entry = Entry(name: name, reason: String(reason))
        if let gitdir = contents("gitdir"), !gitdir.isEmpty {
            entry.path = gitdir.hasSuffix("/.git") ? String(gitdir.dropLast("/.git".count)) : gitdir
        }
        if let head = contents("HEAD") {
            if head.hasPrefix("ref: refs/heads/") {
                entry.branch = String(head.dropFirst("ref: refs/heads/".count))
            } else if !head.isEmpty {
                entry.head = head
            }
        }
        return entry
    }

    /// No branch, tag or remote reaches `commit`. A commit git already collected counts as reachable:
    /// nothing is left to lose.
    private func isUnreachable(_ commit: String, in repo: URL) async throws -> Bool {
        let count = try await git.gitString(
            ["rev-list", "--count", "--ignore-missing", commit, "--not", "--branches", "--tags", "--remotes"],
            in: repo
        )
        return (Int(count) ?? 1) > 0
    }

    /// git prints `Removing worktrees/<name>: <reason>` on stderr.
    private func run(_ arguments: [String], in repo: URL) async throws -> [String] {
        let result = try await git.result(arguments, in: repo)
        guard result.succeeded else {
            throw GitError(exitCode: result.exitCode, stderr: result.stderr, arguments: arguments, timedOut: result.timedOut)
        }
        return Self.parse(result.stderr + "\n" + result.stdoutString)
    }

    static func parse(_ output: String) -> [String] {
        let prefix = "Removing "
        return output.split(separator: "\n").compactMap { line in
            line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : nil
        }
    }
}
