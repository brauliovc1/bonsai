import Foundation

public struct BranchMapEntry: Sendable, Codable, Identifiable, Hashable {
    public enum Kind: String, Sendable, Codable { case branch, remote, worktree, claude, cursor }
    public let ref: String
    public let name: String
    public let sha: String
    public let kind: Kind
    public let worktree: String?
    public let metrics: BranchMapMetrics
    public var id: String { ref }

    public init(ref: String, name: String, sha: String, kind: Kind = .branch, worktree: String? = nil, metrics: BranchMapMetrics) {
        self.ref = ref; self.name = name; self.sha = sha; self.kind = kind; self.worktree = worktree; self.metrics = metrics
    }
    public var compare: CompareSelection { ref.hasPrefix("worktree:") ? worktree.map(CompareSelection.worktree) ?? .ref(sha) : .ref(ref) }
}

/// Only immutable SHA-pair data goes in the cache; names and worktree associations stay fresh.
public struct BranchMapMetrics: Sendable, Codable, Hashable {
    public let ahead: Int?
    public let behind: Int?
    public let fork: BranchHistoryCommit?
    public let tip: BranchHistoryCommit?
    public let problem: String?
    public let commits: [BranchHistoryCommit]
    public var isMerged: Bool { ahead == 0 && problem == nil }

    public init(ahead: Int?, behind: Int?, fork: BranchHistoryCommit?, tip: BranchHistoryCommit?, problem: String? = nil, commits: [BranchHistoryCommit] = []) {
        self.ahead = ahead; self.behind = behind; self.fork = fork; self.tip = tip; self.problem = problem; self.commits = commits
    }
}
