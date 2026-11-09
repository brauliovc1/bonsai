import Foundation

/// The nested-checkout row of PLAN §4.1 (package copies included) and the exact facts the Remove anyway list
/// (§4.8) needs: the submodule paths, and a stamp of each path the worktree itself would lose.
extension WorktreeInspector {
    /// Sorts every checkout below `folder` into what blocks, what is a note, and what git couldn't read:
    /// - registered worktrees (of any scanned repo) and `.git` files: `nestedWorktrees`, always blocking;
    /// - package copies (`PackageCopyRule`, decided without running git in them): build output, a note;
    /// - every other clone or bare repo by what `NestedCloneCheck` finds in it: no local work (a note), local
    ///   work (blocking, with what was found), or unreadable (blocking, with git's first error line).
    func findNested(in folder: URL, knownWorktrees: [Worktree], into state: inout WorktreeState) async {
        let search = nestedSearch.search(folder)
        let registered = knownWorktrees
            .filter { CanonicalPath.isInside($0.url, directory: folder) }
            .compactMap { CanonicalPath.relativePath(of: $0.url, to: folder) }
        let candidates = search.checkouts.filter { !registered.contains($0) && !search.gitFiles.contains($0) }
        let copies = await PackageCopyRule(git: git, worktree: folder).copies(among: candidates)
        let others = candidates.filter { !copies.contains($0) }
        let verdicts = await NestedCloneCheck(git: git).verdicts(others, in: folder)

        state.nestedWorktrees = (registered + search.gitFiles).uniqued().sorted()
        state.packageCopies = candidates.filter(copies.contains).sorted()
        state.nestedClones = others.filter { verdicts[$0] == .clean }.sorted()
        state.nestedLocalWork = others.sorted().compactMap { path in
            guard case .localWork(let found) = verdicts[path] else { return nil }
            return NestedRepo(path: path, findings: found)
        }
        state.nestedUnreadable = others.sorted().compactMap { path in
            guard case .unreadable(let message) = verdicts[path] else { return nil }
            return NestedRepo(path: path, findings: [message])
        }
        state.nestedSearchIncomplete = search.incomplete
    }

    /// The `submodule.<name>.path` values of `.gitmodules`, read with `git config --file` (which runs nothing),
    /// in file order; nil when git can't read the file.
    func submodulePaths(in folder: URL) async -> [String]? {
        let file = folder.appending(path: ".gitmodules")
        guard let result = try? await git.result(["config", "--file", file.path, "--list", "-z"], in: URL(fileURLWithPath: "/")),
              result.succeeded
        else { return nil }
        return NestedRepoConfig.parse(result.stdout).compactMap { key, value in
            key.hasPrefix("submodule.") && key.hasSuffix(".path") ? value : nil
        }.uniqued()
    }

    /// lstat of each path (relative to `folder`; a trailing `/` is dropped), when something is there.
    static func stamps(of paths: [String], in folder: URL) -> [String: FileStamp] {
        var stamps: [String: FileStamp] = [:]
        for path in paths where stamps[path] == nil {
            let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
            stamps[path] = FileStamp.of(folder.appending(path: trimmed).path)
        }
        return stamps
    }
}
