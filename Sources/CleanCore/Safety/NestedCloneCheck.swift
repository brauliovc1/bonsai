import Foundation

/// What a nested repo holds (PLAN §4.1 "Nested checkouts"): no local work (counts like §4.2 build output),
/// local work (each thing found, for the Remove anyway list, §4.8), or a repo git can't read. Package copies
/// never get here: `PackageCopyRule` decides them from their path, without running git in them.
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
/// Every check runs, so the list of what was found is whole. A git error or timeout makes the repo
/// unreadable (git's first error line), and so does a clone where git answers for some other folder (a broken
/// `.git` directory makes git fall back to an enclosing repo).
struct NestedCloneCheck: Sendable {
    var git: Git
    /// Clones checked at the same time.
    var maxConcurrent = 4
    /// Entries of each collapsed ignored folder looked at on disk.
    var ignoredSearchLimit = 10_000

    enum Verdict: Sendable, Hashable {
        /// No local work: it can be fetched again.
        case clean
        /// What was found, in words ("2 unsaved changes", "no remote").
        case localWork([String])
        /// git couldn't read it: git's first error line.
        case unreadable(String)
    }

    /// The verdict for each repo among `relativePaths` (inside `folder`).
    func verdicts(_ relativePaths: [String], in folder: URL) async -> [String: Verdict] {
        let verdicts = await BoundedConcurrency.map(relativePaths, limit: maxConcurrent) { relative in
            await verdict(folder.appending(path: relative, directoryHint: .isDirectory))
        }
        return Dictionary(zip(relativePaths, verdicts), uniquingKeysWith: { first, _ in first })
    }

    /// `submoduleGitDir`: for a submodule's checkout (its `.git` is a file), the git dir that file leads to; the
    /// same rules run through it.
    func verdict(_ repo: URL, submoduleGitDir: URL? = nil) async -> Verdict {
        if submoduleGitDir == nil, NestedCheckoutSearch.isBareRepo(repo) {
            switch await NestedRepoConfig.read(gitDir: repo, git: git) {
            case .failure(let error): return .unreadable(error.message)
            case .success(let config):
                if let key = config.commandKeys.first { return .localWork([Self.commandKeyFinding(key)]) }
                return config.isMirror ? .clean : .localWork(["a bare repo that is not a mirror"])
            }
        }
        let gitDir = submoduleGitDir ?? repo.appending(path: ".git", directoryHint: .isDirectory)
        guard DirectoryEntries.kind(ofItemAt: gitDir.path) == .directory else {
            return .unreadable(submoduleGitDir == nil ? "its .git is not a folder" : "its git dir is not a folder")
        }
        switch await NestedRepoConfig.read(gitDir: gitDir, git: git) {
        case .failure(let error): return .unreadable(error.message)
        case .success(let config):
            if let key = config.commandKeys.first { return .localWork([Self.commandKeyFinding(key)]) }
        }
        do {
            let found = try await localWork(in: repo, gitDir: gitDir)
            return found.isEmpty ? .clean : .localWork(found)
        } catch let error as GitError {
            return .unreadable(Self.firstLine(of: error))
        } catch let error as Unreadable {
            return .unreadable(error.message)
        } catch {
            return .unreadable("\(error)")
        }
    }

    private struct Unreadable: Error {
        var message: String
    }

    private func localWork(in clone: URL, gitDir: URL) async throws -> [String] {
        let topLevel = try await git.gitString(["rev-parse", "--show-toplevel"], in: clone)
        guard CanonicalPath.same(URL(fileURLWithPath: topLevel), clone) else {
            throw Unreadable(message: "git answers for \(topLevel) here, not for this repo")
        }
        var found: [String] = []
        if let marker = WorktreeInspector.operationsInProgress(gitDir: gitDir).first {
            found.append("\(Self.operationName(marker)) in progress")
        }
        if (try await git.gitString(["remote"], in: clone)).isEmpty { found.append("no remote") }
        let changes = WorktreeInspector.countStatusEntries(
            try await git.git(["status", "--porcelain=v1", "-z", "--untracked-files=all"], in: clone)
        )
        if changes > 0 { found.append(Self.count(changes, "unsaved change", "unsaved changes")) }
        let head = try await git.result(["rev-parse", "--verify", "--quiet", "HEAD"], in: clone)
        if head.succeeded {
            let ahead = try await git.gitString(
                ["rev-list", "--count", "HEAD", "--branches", "--not", "--remotes", "--tags"], in: clone
            )
            guard let commits = Int(ahead) else { throw Unreadable(message: "git rev-list said \(ahead)") }
            if commits > 0 { found.append(Self.count(commits, "commit not on a remote", "commits not on a remote")) }
        } else if head.exitCode == 1, head.stderr.isEmpty {
            found.append("no commits yet")
        } else {
            throw GitError(exitCode: head.exitCode, stderr: head.stderr, arguments: ["rev-parse"], timedOut: head.timedOut)
        }
        let stashes = (try await git.gitString(["stash", "list"], in: clone)).split(separator: "\n").count
        if stashes > 0 { found.append(Self.count(stashes, "stash", "stashes")) }

        let inspector = WorktreeInspector(git: git)
        let hidden = try await inspector.hiddenEdits(in: clone)
        if !hidden.isEmpty { found.append("hidden edits: " + hidden.joined(separator: ", ")) }
        if head.succeeded {
            let reflogOnly = try await inspector.reflogOnlyCommits(gitDir: gitDir, in: clone)
            if !reflogOnly.isEmpty {
                found.append(Self.count(reflogOnly.count, "commit only in its reflog", "commits only in its reflog"))
            }
        }
        let ignored = try await git.git(["ls-files", "--others", "--ignored", "--exclude-standard", "--directory", "-z"], in: clone)
        let entries = ignored.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        let userFiles = await IgnoredFileFilter(git: git, folder: clone, searchLimit: ignoredSearchLimit).userFiles(entries)
        if !userFiles.isEmpty { found.append("ignored files: " + userFiles.joined(separator: ", ")) }
        return found
    }

    /// git's first error line ("fatal: bad tree object HEAD"), or what happened when it said nothing.
    static func firstLine(of error: GitError) -> String {
        if error.timedOut { return "git timed out" }
        let line = error.stderr.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return line ?? "git failed (exit \(error.exitCode))"
    }

    private static func commandKeyFinding(_ key: String) -> String {
        "its config sets \(key), so git was not run there"
    }

    private static func count(_ number: Int, _ one: String, _ many: String) -> String {
        "\(number) \(number == 1 ? one : many)"
    }

    private static func operationName(_ marker: String) -> String {
        switch marker {
        case "rebase-merge", "rebase-apply": "a rebase"
        case "MERGE_HEAD": "a merge"
        case "CHERRY_PICK_HEAD": "a cherry-pick"
        case "REVERT_HEAD": "a revert"
        case "BISECT_LOG": "a bisect"
        default: "a git operation"
        }
    }
}
