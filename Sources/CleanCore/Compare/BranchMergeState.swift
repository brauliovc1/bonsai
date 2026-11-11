import Foundation

public struct BranchMergeState: Sendable, Codable, Hashable {
    public enum State: String, Sendable, Codable { case mergeCommit, changesInBase, notMerged, unavailable }
    public let state: State
    public let commit: BranchHistoryCommit?
    public let detail: String?
    public init(_ state: State, commit: BranchHistoryCommit? = nil, detail: String? = nil) {
        self.state = state; self.commit = commit; self.detail = detail
    }
}
