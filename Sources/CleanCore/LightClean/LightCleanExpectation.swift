import Foundation

/// Whose worktree the person was shown when they confirmed a light clean: the repo, the folder, the branch and
/// HEAD of git's record at that moment. Given to `LightCleaner`, it refuses when the fresh record differs, so
/// nothing is deleted in a worktree that is not the one that was listed.
public struct LightCleanExpectation: Sendable, Hashable {
    public var repoPath: String
    public var path: String
    public var branch: String?
    public var head: String?

    public init(worktree: Worktree) {
        repoPath = worktree.repoPath
        path = worktree.path
        branch = worktree.branch
        head = worktree.head
    }

    /// What differs from the confirmation, one sentence each; empty when nothing does.
    public func changes(fresh worktree: Worktree) -> [String] {
        var changes: [String] = []
        if !CanonicalPath.same(worktree.repoURL, URL(fileURLWithPath: repoPath, isDirectory: true)) {
            changes.append("It is now listed by \(worktree.repoPath), not \(repoPath).")
        }
        if !CanonicalPath.same(worktree.url, URL(fileURLWithPath: path, isDirectory: true)) {
            changes.append("It is now at \(worktree.path), not \(path).")
        }
        if worktree.branch != branch {
            changes.append("The branch is now \(RemovalExpectation.name(worktree.branch)) (was \(RemovalExpectation.name(branch))).")
        }
        if worktree.head != head {
            changes.append("HEAD moved from \(RemovalExpectation.short(head)) to \(RemovalExpectation.short(worktree.head)).")
        }
        return changes
    }
}
