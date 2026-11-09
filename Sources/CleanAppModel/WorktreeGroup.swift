import CleanCore
import Foundation

/// One repo on the Worktrees screen: its header (name, folder, remote, how many worktrees, their size) and
/// its shown rows, the main checkout first.
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
    /// The rows shown (filters and search applied), sorted, the main checkout first.
    public let rows: [WorktreeRow]
    /// Every worktree of the repo in the scan, shown or not.
    public let totalCount: Int

    public init(repoPath: String, rows: [WorktreeRow], totalCount: Int, remotes: [GitRemote], home: URL?) {
        self.repoPath = repoPath
        self.name = DisplayText.repoName(repoPath)
        self.folderText = home.map { TildePath.abbreviate(repoPath, home: $0) } ?? repoPath
        self.remotes = remotes
        self.remoteText = DisplayText.remotes(remotes, home: home)
        self.rows = rows
        self.totalCount = totalCount
    }

    public var id: String { repoPath }

    /// "4 worktrees", or "2 of 4 worktrees" when filters or search hide some.
    public var countText: String {
        rows.count == totalCount ? DisplayText.worktrees(totalCount) : "\(rows.count) of \(DisplayText.worktrees(totalCount))"
    }

    /// The shown rows' estimated sizes added up; nil when none is known.
    public var totalBytes: Int64? {
        let sizes = rows.compactMap(\.sizeBytes)
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
