import Foundation

/// Decides which nested clones hold no local work (PLAN §4.1 "Nested checkouts"): package managers' clones
/// (SwiftPM `.build/checkouts`, Xcode `SourcePackages/checkouts`) can be fetched again, so they count like §4.2
/// build output.
///
/// A clone holds no local work when all of these hold, each run inside the clone:
/// - it has at least one remote (`git remote`);
/// - `git status --porcelain` is empty;
/// - `git rev-list --count HEAD --branches --not --remotes --tags` is 0;
/// - `git stash list` is empty.
/// Any git error or timeout counts as local work, and so does a clone where git answers for some other
/// folder (a broken `.git` directory makes git fall back to an enclosing repo).
struct NestedCloneCheck: Sendable {
    var git: Git
    /// Clones checked at the same time.
    var maxConcurrent = 4

    /// The clones among `relativePaths` (inside `folder`) that hold no local work.
    func clonesWithoutLocalWork(_ relativePaths: [String], in folder: URL) async -> Set<String> {
        let verdicts = await BoundedConcurrency.map(relativePaths, limit: maxConcurrent) { relative in
            await holdsNoLocalWork(folder.appending(path: relative, directoryHint: .isDirectory))
        }
        return Set(zip(relativePaths, verdicts).filter(\.1).map(\.0))
    }

    func holdsNoLocalWork(_ clone: URL) async -> Bool {
        do {
            let topLevel = try await git.gitString(["rev-parse", "--show-toplevel"], in: clone)
            guard CanonicalPath.same(URL(fileURLWithPath: topLevel), clone) else { return false }
            guard !(try await git.gitString(["remote"], in: clone)).isEmpty else { return false }
            guard (try await git.gitString(["status", "--porcelain"], in: clone)).isEmpty else { return false }
            let ahead = try await git.gitString(
                ["rev-list", "--count", "HEAD", "--branches", "--not", "--remotes", "--tags"],
                in: clone
            )
            guard ahead == "0" else { return false }
            return (try await git.gitString(["stash", "list"], in: clone)).isEmpty
        } catch {
            return false
        }
    }
}
