import Foundation

/// One working tree registered to a repo, as reported by `git worktree list --porcelain -z`.
///
/// Paths are plain strings (lexically standardized, symlinks not resolved) so the type stays trivially
/// `Codable` and `Hashable`; use `url` / `repoURL` for file APIs and `CanonicalPath` to compare.
public struct Worktree: Sendable, Codable, Hashable, Identifiable {
    /// The worktree folder as git reports it.
    public var path: String
    /// The main repo folder the scan ran git in.
    public var repoPath: String
    /// HEAD commit; nil for a bare entry.
    public var head: String?
    /// Branch name without `refs/heads/`; nil when detached (or bare).
    public var branch: String?
    public var isMain: Bool
    public var isBare: Bool
    /// nil = not locked, "" = locked without a reason.
    public var lockedReason: String?
    /// nil = not prunable (git reports prunable when the folder is gone).
    public var prunableReason: String?
    public var kind: WorktreeKind

    public init(
        path: String,
        repoPath: String,
        head: String?,
        branch: String?,
        isMain: Bool,
        isBare: Bool = false,
        lockedReason: String? = nil,
        prunableReason: String? = nil,
        kind: WorktreeKind
    ) {
        self.path = Self.standardize(path)
        self.repoPath = Self.standardize(repoPath)
        self.head = head
        self.branch = branch
        self.isMain = isMain
        self.isBare = isBare
        self.lockedReason = lockedReason
        self.prunableReason = prunableReason
        self.kind = kind
    }

    /// The standardized path.
    public var id: String { path }

    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
    public var repoURL: URL { URL(fileURLWithPath: repoPath, isDirectory: true) }

    public var isDetached: Bool { branch == nil && !isBare }
    public var isLocked: Bool { lockedReason != nil }
    public var isPrunable: Bool { prunableReason != nil }

    /// Lexical standardization only: removes `.`, `..` and trailing slashes, never touches the disk.
    public static func standardize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardized.path
    }
}
