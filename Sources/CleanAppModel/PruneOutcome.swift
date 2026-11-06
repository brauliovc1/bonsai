import Foundation

/// What `git worktree prune` did for one repo.
public struct PruneOutcome: Identifiable, Sendable {
    public let repoPath: String
    /// `worktrees/<name>: <reason>` per cleared record.
    public let pruned: [String]
    /// Why the repo's prune was refused (git prunes a whole repo at once).
    public let refusals: [String]
    public let error: String?
    public let warnings: [String]

    public var id: String { repoPath }
    public var repoName: String { DisplayText.repoName(repoPath) }

    /// One line for the result alert.
    public var summary: String {
        if !refusals.isEmpty { return "\(repoName): refused, nothing cleared. " + refusals.joined(separator: "; ") }
        if let error { return "\(repoName): \(error)" }
        if pruned.isEmpty { return "\(repoName): nothing to clear." }
        let records = pruned.count == 1 ? "1 missing folder" : "\(pruned.count) missing folders"
        return "\(repoName): cleared git's record of \(records)."
            + (warnings.isEmpty ? "" : " " + warnings.joined(separator: " "))
    }
}
