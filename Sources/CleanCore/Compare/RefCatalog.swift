import Foundation

public struct RefCatalog: Sendable {
    public struct Ref: Sendable, Hashable, Identifiable {
        public enum Kind: String, Sendable { case local, remote, tag }
        public let name: String
        public let fullName: String
        public let sha: String
        public let kind: Kind
        public var id: String { fullName }
    }
    public let refs: [Ref]
    public let worktrees: [Worktree]
    public let defaultBase: String?
    public let lastFetch: Date?

    public static func load(using git: GitReadOnly) async throws -> RefCatalog {
        let output = try await git.string(["for-each-ref", "--format=%(refname)%00%(objectname)", "--sort=refname", "refs/heads", "refs/remotes", "refs/tags"])
        let refs = output.split(separator: "\n").compactMap { line -> Ref? in
            let parts = line.split(separator: "\0", omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            let full = String(parts[0])
            let kind: Ref.Kind = full.hasPrefix("refs/heads/") ? .local : full.hasPrefix("refs/remotes/") ? .remote : .tag
            let prefix = kind == .local ? "refs/heads/" : kind == .remote ? "refs/remotes/" : "refs/tags/"
            return Ref(name: String(full.dropFirst(prefix.count)), fullName: full, sha: String(parts[1]), kind: kind)
        }
        let symbolic = try? await git.string(["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"])
        let fallback = ["main", "master"].first { name in refs.contains { $0.kind == .local && $0.name == name } }
        let data = try await git.data(["worktree", "list", "--porcelain", "-z"])
        let records = WorktreeListParser.parse(data)
        let main = URL(fileURLWithPath: records.first?.path ?? git.repository.path)
        let worktrees = records.enumerated().map { index, record in
            Worktree(path: record.path, repoPath: git.repository.path, head: record.head, branch: record.branch,
                isMain: index == 0, isBare: record.isBare, lockedReason: record.lockedReason,
                prunableReason: record.prunableReason,
                kind: WorktreeKind.classify(path: URL(fileURLWithPath: record.path), isMain: index == 0,
                    mainPath: main, cursorWorktreesDirectory: URL(fileURLWithPath: "/nonexistent")))
        }
        let fetch = try? FileManager.default.attributesOfItem(atPath: git.commonDirectory.appending(path: "FETCH_HEAD").path)[.modificationDate] as? Date
        return RefCatalog(refs: refs, worktrees: worktrees, defaultBase: symbolic ?? fallback, lastFetch: fetch ?? nil)
    }
}
