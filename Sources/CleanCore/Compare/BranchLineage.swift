import Foundation

/// The history card is data: every assertion retains its evidence or an explicit uncertainty.
public struct BranchLineage: Sendable, Codable {
    public enum ForkSource: String, Sendable, Codable { case parentReflog, mergeBase, creationRecord, unavailable }
    public let branch: String
    public let base: String
    public let tip: BranchHistoryCommit
    public let origin: BranchOrigin
    public let forkPoint: BranchHistoryCommit?
    public let forkSource: ForkSource
    public let merged: BranchMergeState
    public let children: [String]
    public let parentChain: BranchFamily.Chain
    public let upstream: BranchUpstream
    public let worktree: String?
    public let problems: [String]
}
