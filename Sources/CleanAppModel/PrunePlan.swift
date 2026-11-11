import CleanCore
import Foundation

/// What the prune sheet shows before anything is cleared: per repo with a missing folder among the shown
/// rows, the records `git worktree prune` would clear right now (`Pruner.preview`). Only these repos are
/// pruned, and each only while its fresh preview still has exactly these entries.
public struct PrunePlan: Sendable {
    public struct Repo: Identifiable, Sendable {
        public let repoPath: String
        public let entries: [Pruner.Entry]
        /// Why this repo can't be pruned (git prunes a whole repo at once).
        public let refusals: [String]
        /// The preview itself failed.
        public let error: String?

        public var id: String { repoPath }
        public var repoName: String { DisplayText.repoName(repoPath) }
        public var canPrune: Bool { error == nil && refusals.isEmpty && !entries.isEmpty }
    }

    public let repos: [Repo]

    public var prunable: [Repo] { repos.filter(\.canPrune) }
    public var entryCount: Int { prunable.reduce(0) { $0 + $1.entries.count } }

    /// "Clear 2 records".
    public var buttonTitle: String { entryCount == 1 ? "Clear 1 record" : "Clear \(entryCount) records" }

    /// "/path/to/folder (branch gone)" or "(detached at 1a2b3c4d)".
    public static func describe(_ entry: Pruner.Entry) -> String {
        let ref = entry.branch.map { "branch \($0)" } ?? entry.head.map { "detached at \($0.prefix(8))" } ?? "no HEAD"
        return "\(entry.path ?? "worktrees/\(entry.name)") (\(ref))"
    }
    public var title: String { entryCount == 0 ? "Nothing to clear" : "Clear \(entryCount) missing folder \(entryCount == 1 ? "record" : "records")?" }

}
