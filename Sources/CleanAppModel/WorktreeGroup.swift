import CleanCore
import Foundation

/// One repo on the Worktrees screen. Its header is the repo's main checkout (PLAN §8.4), which is never a row
/// and never removable: "aitiu0 · repo folder · 120 MB · 2 worktrees · last commit 10 weeks ago". The rows are
/// its linked worktrees the filter and search show.
public struct WorktreeGroup: Identifiable, Hashable, Sendable {
    /// The main repo folder.
    public let repoPath: String
    public let name: String
    /// The repo folder with "~" for the home folder ("~/Documents/GitHub/Nexus").
    public let folderText: String
    /// The repo's remotes, "origin" first, URLs without credentials.
    public let remotes: [GitRemote]
    /// "github.com/brauliovc1/Nexus", "+N" for more remotes; nil without one.
    public let remoteText: String?
    /// The repo folder itself, from the scan; nil when the scan has no record of it.
    public let main: WorktreeRow?
    /// The linked worktrees shown (filter and search applied), sorted.
    public let rows: [WorktreeRow]
    /// Every linked worktree of the repo in the scan, shown or not.
    public let totalCount: Int
    /// Their estimated sizes added up (unknown sizes left out); nil when none is known.
    public let worktreeBytes: Int64?

    public init(
        repoPath: String,
        main: WorktreeRow?,
        rows: [WorktreeRow],
        totalCount: Int,
        worktreeBytes: Int64? = nil,
        remotes: [GitRemote],
        home: URL?
    ) {
        self.repoPath = repoPath
        self.name = DisplayText.repoName(repoPath)
        self.folderText = home.map { TildePath.abbreviate(repoPath, home: $0) } ?? repoPath
        self.remotes = remotes
        self.remoteText = DisplayText.remotes(remotes, home: home)
        self.main = main
        self.rows = rows
        self.totalCount = totalCount
        self.worktreeBytes = worktreeBytes
    }

    public var id: String { repoPath }

    /// "2 worktrees".
    public var countText: String { DisplayText.worktrees(totalCount) }

    /// The header's second part: "repo folder 120 MB · 2 worktrees, 3.7 GB · last commit 10 weeks ago".
    public var headerDetail: String {
        let folder = main.map { $0.isMeasuringSize ? "repo folder measuring…" : "repo folder \(DisplayText.bytes($0.sizeBytes))" }
        var parts = [folder ?? "repo folder"]
        parts.append(worktreeBytes.map { "\(countText), \(DisplayText.bytes($0))" } ?? countText)
        if let main, let commit = main.lastCommit {
            parts.append("last commit \(DisplayText.timeAgo(commit.date, now: main.now))")
        }
        return parts.joined(separator: " · ")
    }

    /// The shown rows that can be removed ("Remove all N").
    public var removableRows: [WorktreeRow] { rows.filter(\.canRemove) }

    /// The repo folder's dependency and build folders that "Clean dependencies…" would delete; nil until they
    /// are measured, or when there are none.
    public var dependencyBytes: Int64? {
        guard let bytes = main?.dependencyBytes, bytes > 0 else { return nil }
        return bytes
    }

    /// The repo folder and its shown worktrees together; nil when no size is known.
    public var totalBytes: Int64? {
        let sizes = ([main].compactMap { $0 } + rows).compactMap(\.sizeBytes)
        return sizes.isEmpty ? nil : sizes.reduce(0, +)
    }

    public var sizeText: String { DisplayText.bytes(totalBytes) }

    /// The remotes in full, one per line, for the header's tooltip.
    public var remotesHelp: String {
        guard !remotes.isEmpty else { return "No remote" }
        return remotes.map { remote in
            "\(remote.name): \(remote.url)" + (remote.pushURL.map { " (push: \($0))" } ?? "")
        }.joined(separator: "\n")
    }
}
