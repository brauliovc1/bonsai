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

    /// Whose folder it is now.
    public enum Identity: Sendable, Hashable {
        /// The folder's `.git` leads back to this repo; `gitDir` is the git dir git uses there.
        case this(gitDir: URL)
        /// The folder's `.git` leads to a git dir that is not this repo's (the path).
        case staleRecord(leadsTo: String)
        /// git could not say (no `.git` of its own, or a git command failed).
        case unreadable(String)
    }

    /// Whether the folder at `worktree.path` is still this repo's worktree. Without its own `.git` file,
    /// git commands in the folder would describe an enclosing repo; and a linked worktree's `.git` file
    /// must lead back to one of this repo's records (`<common dir>/worktrees/`). When it leads to
    /// another repo's, the record is stale (another repo's worktree now lives at the path) and every fact
    /// read there would describe that other worktree. A main checkout's `.git` must be this repo's git dir.
    public func identity(of worktree: Worktree) async -> Identity {
        let folder = worktree.url
        do {
            let topLevel = try await git.gitString(["rev-parse", "--show-toplevel"], in: folder)
            guard CanonicalPath.same(URL(fileURLWithPath: topLevel), folder) else {
                return .unreadable("git sees \(topLevel) here, not this worktree; its .git file is missing or broken")
            }
            let gitDir = URL(fileURLWithPath: try await git.gitString(["rev-parse", "--absolute-git-dir"], in: folder))
            let commonDir = URL(fileURLWithPath: try await git.gitString(
                ["rev-parse", "--path-format=absolute", "--git-common-dir"],
                in: worktree.repoURL
            ))
            let leadsHome = if worktree.isMain {
                CanonicalPath.same(gitDir, commonDir)
            } else {
                CanonicalPath.isInside(gitDir, directory: commonDir.appending(path: "worktrees", directoryHint: .isDirectory))
            }
            return leadsHome ? .this(gitDir: gitDir) : .staleRecord(leadsTo: gitDir.path)
        } catch {
            return .unreadable("\(error)")
        }
    }

    /// `knownWorktrees`: every registered worktree of every scanned repo; any inside this one counts as a
    /// nested checkout.
    public func inspect(_ worktree: Worktree, knownWorktrees: [Worktree] = []) async -> WorktreeState {
        let folder = worktree.url
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue
        else { return .missing }

        var state = WorktreeState()
        let gitDir: URL
        switch await identity(of: worktree) {
        case .this(let found): gitDir = found
        case .staleRecord(let leadsTo):
            state.staleRecord = leadsTo
            return state
        case .unreadable(let message):
            state.gitErrors.append(message)
            return state
        }

        state.hasSubmodules = FileManager.default.fileExists(atPath: folder.appending(path: ".gitmodules").path)
        if state.hasSubmodules { state.submodulePaths = await submodulePaths(in: folder) }
        state.operationsInProgress = Self.operationsInProgress(gitDir: gitDir)

        var errors: [String] = []
        let status = await attempt(&errors) {
            try await git.git(["status", "--porcelain=v1", "-z", "--untracked-files=all"], in: folder)
        }
        state.changedFiles = status.map(Self.countStatusEntries) ?? 0
        state.changedPaths = status.map(GitStatusEntry.parse) ?? []
        state.hiddenEdits = await attempt(&errors) { try await hiddenEdits(in: folder) } ?? []
        if worktree.isDetached {
            // The commits themselves: a detached worktree can't be removed with them, except by Remove anyway,
            // which lists each one.
            state.localOnlyShas = await attempt(&errors) {
                try await git.gitString(["rev-list", "HEAD", "--not", "--remotes"], in: folder)
                    .split(separator: "\n").map(String.init)
            } ?? []
            state.localOnlyCommits = state.localOnlyShas.count
            state.reflogOnlyShas = await attempt(&errors) { try await reflogOnlyCommits(gitDir: gitDir, in: folder) } ?? []
            state.reflogOnlyCommits = state.reflogOnlyShas.count
        } else {
            state.localOnlyCommits = await attempt(&errors) {
                let count = try await git.gitString(["rev-list", "--count", "HEAD", "--not", "--remotes"], in: folder)
                guard let value = Int(count) else { throw GitError(exitCode: 0, stderr: count, arguments: ["rev-list"]) }
                return value
            } ?? 0
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
        state.pathStamps = Self.stamps(of: state.changedPaths.map(\.path) + state.hiddenEdits + state.ignoredUserFiles, in: folder)

        await findNested(in: folder, knownWorktrees: knownWorktrees, into: &state)
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
