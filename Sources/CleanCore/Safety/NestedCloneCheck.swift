import Foundation

/// Decides which nested repos hold no local work (PLAN §4.1 "Nested checkouts"): package managers' clones
/// (SwiftPM `.build/checkouts`, Xcode `SourcePackages/checkouts`) and mirrors (their `repositories/`) can be
/// fetched again, so they count like §4.2 build output.
///
/// First the repo's own config is read without running anything (`NestedRepoConfig`): a key that makes git
/// run a command or read another file is local work, and git is not run there.
///
/// A bare repo holds no local work only when it is a mirror. A clone holds none when all of these hold,
/// each run inside the clone (the same rows as for a worktree):
/// - it has at least one remote (`git remote`);
/// - `git status --porcelain --untracked-files=all` is empty (whatever `status.showUntrackedFiles` says);
/// - `git rev-list --count HEAD --branches --not --remotes --tags` is 0;
/// - `git stash list` is empty;
/// - no hidden local edits (`ls-files -v`: assume-unchanged or skip-worktree files on disk);
/// - no operation in progress, no reflog-only commits in its own `logs/HEAD`;
/// - no ignored files other than §4.2 build output.
/// Any git error or timeout counts as local work, and so does a clone where git answers for some other
/// folder (a broken `.git` directory makes git fall back to an enclosing repo).
struct NestedCloneCheck: Sendable {
    var git: Git
    /// Clones checked at the same time.
    var maxConcurrent = 4
    /// Entries of each collapsed ignored folder looked at on disk.
    var ignoredSearchLimit = 10_000

    /// The repos among `relativePaths` (inside `folder`) that hold no local work.
    func clonesWithoutLocalWork(_ relativePaths: [String], in folder: URL) async -> Set<String> {
        let verdicts = await BoundedConcurrency.map(relativePaths, limit: maxConcurrent) { relative in
            await holdsNoLocalWork(folder.appending(path: relative, directoryHint: .isDirectory))
        }
        return Set(zip(relativePaths, verdicts).filter(\.1).map(\.0))
    }

    func holdsNoLocalWork(_ repo: URL) async -> Bool {
        if NestedCheckoutSearch.isBareRepo(repo) {
            guard let config = await NestedRepoConfig.read(gitDir: repo, git: git) else { return false }
            return config.commandKeys.isEmpty && config.isMirror
        }
        let gitDir = repo.appending(path: ".git", directoryHint: .isDirectory)
        guard DirectoryEntries.kind(ofItemAt: gitDir.path) == .directory,
              let config = await NestedRepoConfig.read(gitDir: gitDir, git: git),
              config.commandKeys.isEmpty
        else { return false }
        do {
            return try await cloneHoldsNoLocalWork(repo, gitDir: gitDir)
        } catch {
            return false
        }
    }

    private func cloneHoldsNoLocalWork(_ clone: URL, gitDir: URL) async throws -> Bool {
        let topLevel = try await git.gitString(["rev-parse", "--show-toplevel"], in: clone)
        guard CanonicalPath.same(URL(fileURLWithPath: topLevel), clone) else { return false }
        guard WorktreeInspector.operationsInProgress(gitDir: gitDir).isEmpty else { return false }
        guard !(try await git.gitString(["remote"], in: clone)).isEmpty else { return false }
        guard (try await git.gitString(["status", "--porcelain", "--untracked-files=all"], in: clone)).isEmpty else {
            return false
        }
        let ahead = try await git.gitString(["rev-list", "--count", "HEAD", "--branches", "--not", "--remotes", "--tags"], in: clone)
        guard ahead == "0" else { return false }
        guard (try await git.gitString(["stash", "list"], in: clone)).isEmpty else { return false }

        let inspector = WorktreeInspector(git: git)
        guard try await inspector.hiddenEdits(in: clone).isEmpty else { return false }
        guard try await inspector.reflogOnlyCommits(gitDir: gitDir, in: clone) == 0 else { return false }
        let ignored = try await git.git(["ls-files", "--others", "--ignored", "--exclude-standard", "--directory", "-z"], in: clone)
        let entries = ignored.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        return await IgnoredFileFilter(git: git, folder: clone, searchLimit: ignoredSearchLimit).userFiles(entries).isEmpty
    }
}
