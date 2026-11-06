import Foundation

/// Reads the git and disk state the §4.1 checks need for one linked worktree. Read-only.
public struct WorktreeInspector: Sendable {
    public var git: Git
    /// How many entries of each collapsed ignored folder are looked at on disk.
    public var ignoredSearchLimit: Int
    public var nestedSearch: NestedCheckoutSearch

    public init(git: Git, ignoredSearchLimit: Int = 10_000, nestedSearch: NestedCheckoutSearch = NestedCheckoutSearch()) {
        self.git = git
        self.ignoredSearchLimit = ignoredSearchLimit
        self.nestedSearch = nestedSearch
    }

    /// `knownWorktrees`: every registered worktree of every scanned repo; any inside this one counts as a
    /// nested checkout.
    public func inspect(_ worktree: Worktree, knownWorktrees: [Worktree] = []) async -> WorktreeState {
        let folder = worktree.url
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue
        else { return .missing }

        var state = WorktreeState()
        // Without its own `.git` file, git commands in the folder would describe an enclosing repo.
        let gitDir: URL
        do {
            let topLevel = try await git.gitString(["rev-parse", "--show-toplevel"], in: folder)
            guard CanonicalPath.same(URL(fileURLWithPath: topLevel), folder) else {
                state.gitErrors.append("git sees \(topLevel) here, not this worktree; its .git file is missing or broken")
                return state
            }
            gitDir = URL(fileURLWithPath: try await git.gitString(["rev-parse", "--absolute-git-dir"], in: folder))
            // The folder's `.git` file must lead back to one of this repo's records (`<common dir>/worktrees/`).
            // When it leads to another repo's, this record is stale (another repo's worktree now lives at the
            // path) and every fact below would describe that other worktree.
            let commonDir = try await git.gitString(
                ["rev-parse", "--path-format=absolute", "--git-common-dir"],
                in: worktree.repoURL
            )
            let records = URL(fileURLWithPath: commonDir).appending(path: "worktrees", directoryHint: .isDirectory)
            guard CanonicalPath.isInside(gitDir, directory: records) else {
                state.staleRecord = gitDir.path
                return state
            }
        } catch {
            state.gitErrors.append("\(error)")
            return state
        }

        state.hasSubmodules = FileManager.default.fileExists(atPath: folder.appending(path: ".gitmodules").path)
        state.operationsInProgress = Self.operationsInProgress(gitDir: gitDir)

        var errors: [String] = []
        state.changedFiles = await attempt(&errors) {
            Self.countStatusEntries(try await git.git(["status", "--porcelain=v1", "-z", "--untracked-files=all"], in: folder))
        } ?? 0
        state.hiddenEdits = await attempt(&errors) { try await hiddenEdits(in: folder) } ?? []
        state.localOnlyCommits = await attempt(&errors) {
            let count = try await git.gitString(["rev-list", "--count", "HEAD", "--not", "--remotes"], in: folder)
            guard let value = Int(count) else { throw GitError(exitCode: 0, stderr: count, arguments: ["rev-list"]) }
            return value
        } ?? 0
        if worktree.isDetached {
            state.reflogOnlyCommits = await attempt(&errors) { try await reflogOnlyCommits(gitDir: gitDir, in: folder) } ?? 0
        }
        if let branch = worktree.branch {
            state.branchStashes = await attempt(&errors) {
                Self.countStashes(try await git.gitString(["stash", "list", "--format=%gs"], in: folder), branch: branch)
            } ?? 0
        }
        state.ignoredUserFiles = await attempt(&errors) {
            let output = try await git.git(
                ["ls-files", "--others", "--ignored", "--exclude-standard", "--directory", "-z"],
                in: folder
            )
            let ignored = output.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
            return await IgnoredFileFilter(git: git, folder: folder, searchLimit: ignoredSearchLimit).userFiles(ignored)
        } ?? []
        state.gitErrors += errors

        // Registered worktrees (of any scanned repo) and `.git` files always block; a plain clone blocks
        // unless it holds no local work.
        let search = nestedSearch.search(folder)
        let registered = knownWorktrees
            .filter { CanonicalPath.isInside($0.url, directory: folder) }
            .compactMap { CanonicalPath.relativePath(of: $0.url, to: folder) }
        let candidates = search.checkouts.filter { !registered.contains($0) && !search.gitFiles.contains($0) }
        let clean = await NestedCloneCheck(git: git).clonesWithoutLocalWork(candidates, in: folder)
        state.nestedCheckouts = (registered + search.checkouts.filter { !clean.contains($0) }).uniqued().sorted()
        state.nestedClones = candidates.filter(clean.contains).sorted()
        state.nestedSearchIncomplete = search.incomplete
        return state
    }

    /// Runs one check; a failure is recorded in `errors` (any git error blocks removal) and gives nil.
    private func attempt<T>(_ errors: inout [String], _ check: () async throws -> T) async -> T? {
        do {
            return try await check()
        } catch {
            errors.append("\(error)")
            return nil
        }
    }

    /// Entries of `status --porcelain=v1 -z`. A rename or copy (`R`/`C`) is followed by its source path,
    /// which is not a separate entry.
    static func countStatusEntries(_ data: Data) -> Int {
        let fields = data.split(separator: 0)
        var count = 0
        var index = fields.startIndex
        while index < fields.endIndex {
            let field = fields[index]
            count += 1
            let codes = field.prefix(2)
            index += codes.contains(UInt8(ascii: "R")) || codes.contains(UInt8(ascii: "C")) ? 2 : 1
        }
        return count
    }

    /// Stash subjects made on `branch`: `WIP on <branch>: ...` or `On <branch>: ...`.
    static func countStashes(_ output: String, branch: String) -> Int {
        output.split(separator: "\n").filter { line in
            line.hasPrefix("WIP on \(branch):") || line.hasPrefix("On \(branch):")
        }.count
    }
}
