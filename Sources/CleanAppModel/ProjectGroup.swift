import CleanCore
import Foundation

/// One repo on the Project folders screen: its header (name, folder, how many projects, their size) and its
/// shown rows.
public struct ProjectGroup: Identifiable, Hashable, Sendable {
    public let repoPath: String
    public let name: String
    /// The repo folder with "~".
    public let folderText: String
    /// The rows shown (filter applied), sorted.
    public let rows: [ProjectRow]
    /// The repo's projects in the scan, shown or not.
    public let totalCount: Int

    public init(repoPath: String, rows: [ProjectRow], totalCount: Int, home: URL?) {
        self.repoPath = repoPath
        self.name = DisplayText.repoName(repoPath)
        self.folderText = home.map { TildePath.abbreviate(repoPath, home: $0) } ?? repoPath
        self.rows = rows
        self.totalCount = totalCount
    }

    public var id: String { repoPath }
    public var totalBytes: Int64 { rows.reduce(0) { $0 + $1.sizeBytes } }
    public var sizeText: String { DisplayText.bytes(totalBytes) }

    /// "2 projects", or "1 of 2 projects" when the filter hides some.
    public var countText: String {
        rows.count == totalCount ? DisplayText.projects(totalCount) : "\(rows.count) of \(DisplayText.projects(totalCount))"
    }
}

extension DisplayText {
    /// "1 project", "3 projects".
    public static func projects(_ count: Int) -> String {
        count == 1 ? "1 project" : "\(count) projects"
    }
}
