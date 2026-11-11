import Foundation

public struct BranchTimelineEntry: Sendable, Codable {
    public let ref: String
    public let fork: BranchHistoryCommit?
    public let commits: [BranchHistoryCommit]
    public let commitCount: Int
    public let problem: String?
}
