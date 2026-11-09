/// What `WorktreeInspector` read from git and the disk for one worktree: the facts the §4.1 checks need, and
/// the exact entries the Remove anyway list (§4.8) is built from.
public struct WorktreeState: Sendable, Hashable {
    public var folderExists: Bool
    /// Entries of `git status --porcelain=v1 -z --untracked-files=all`.
    public var changedFiles: Int
    /// Those entries, as git listed them (the inspector fills both; `changedFiles` alone means not listed).
    public var changedPaths: [GitStatusEntry]
    /// `assume-unchanged` / `skip-worktree` files present on disk: edits `git status` never shows.
    public var hiddenEdits: [String]
    /// Markers of a half-done rebase, merge, cherry-pick, revert or bisect in the worktree's git dir.
    public var operationsInProgress: [String]
    /// `.gitmodules` is present.
    public var hasSubmodules: Bool
    /// The `submodule.*.path` values of `.gitmodules`; nil when it couldn't be read (or isn't there).
    public var submodulePaths: [String]?
    /// `git rev-list --count HEAD --not --remotes`.
    public var localOnlyCommits: Int
    /// Detached only: those commits (full shas, newest first).
    public var localOnlyShas: [String]
    /// Detached only: commits named in the worktree's own `logs/HEAD` that no branch, tag or remote reaches.
    public var reflogOnlyCommits: Int
    /// Detached only: those commits (full shas).
    public var reflogOnlyShas: [String]
    /// Stash entries made on this worktree's branch (0 when detached).
    public var branchStashes: Int
    /// Ignored files and folders that are not regenerable (§4.2), relative to the worktree.
    public var ignoredUserFiles: [String]
    /// What lstat saw at each path of `changedPaths`, `hiddenEdits` and `ignoredUserFiles` when they were read.
    public var pathStamps: [String: FileStamp]
    /// Registered worktrees (of any scanned repo) and `.git` files (a linked worktree or submodule of some repo)
    /// inside: nothing is known about what they hold.
    public var nestedWorktrees: [String]
    /// Clones and bare repos inside with local work, each with what was found.
    public var nestedLocalWork: [NestedRepo]
    /// Repos inside that git couldn't read, each with git's first error line.
    public var nestedUnreadable: [NestedRepo]
    /// Nested clones with no local work: deleted with the worktree, fetched again when needed. Shown, never
    /// blocking.
    public var nestedClones: [String]
    /// Package managers' copies inside ignored build folders (§4.1 "Package copies"): build output.
    public var packageCopies: [String]
    /// Why the nested-checkout search could not look everywhere (entry cap, unreadable folder).
    public var nestedSearchIncomplete: String?
    /// Every git command that failed. Any error blocks removal.
    public var gitErrors: [String]
    /// The git dir the folder's `.git` file leads to when that is not one of this repo's records: git's
    /// record of this worktree is stale and the folder belongs to another repo.
    public var staleRecord: String?

    public init(
        folderExists: Bool = true,
        changedFiles: Int = 0,
        changedPaths: [GitStatusEntry] = [],
        hiddenEdits: [String] = [],
        operationsInProgress: [String] = [],
        hasSubmodules: Bool = false,
        submodulePaths: [String]? = nil,
        localOnlyCommits: Int = 0,
        localOnlyShas: [String] = [],
        reflogOnlyCommits: Int = 0,
        reflogOnlyShas: [String] = [],
        branchStashes: Int = 0,
        ignoredUserFiles: [String] = [],
        pathStamps: [String: FileStamp] = [:],
        nestedWorktrees: [String] = [],
        nestedLocalWork: [NestedRepo] = [],
        nestedUnreadable: [NestedRepo] = [],
        nestedClones: [String] = [],
        packageCopies: [String] = [],
        nestedSearchIncomplete: String? = nil,
        gitErrors: [String] = [],
        staleRecord: String? = nil
    ) {
        self.folderExists = folderExists
        self.changedFiles = changedFiles
        self.changedPaths = changedPaths
        self.hiddenEdits = hiddenEdits
        self.operationsInProgress = operationsInProgress
        self.hasSubmodules = hasSubmodules
        self.submodulePaths = submodulePaths
        self.localOnlyCommits = localOnlyCommits
        self.localOnlyShas = localOnlyShas
        self.reflogOnlyCommits = reflogOnlyCommits
        self.reflogOnlyShas = reflogOnlyShas
        self.branchStashes = branchStashes
        self.ignoredUserFiles = ignoredUserFiles
        self.pathStamps = pathStamps
        self.nestedWorktrees = nestedWorktrees
        self.nestedLocalWork = nestedLocalWork
        self.nestedUnreadable = nestedUnreadable
        self.nestedClones = nestedClones
        self.packageCopies = packageCopies
        self.nestedSearchIncomplete = nestedSearchIncomplete
        self.gitErrors = gitErrors
        self.staleRecord = staleRecord
    }

    public static let missing = WorktreeState(folderExists: false)

    /// Other checkouts inside that may hold work: registered worktrees, `.git` files and repos with local
    /// work. `git worktree remove` would delete them along with it. (Unreadable repos are their own reason.)
    public var nestedCheckouts: [String] {
        (nestedWorktrees + nestedLocalWork.map(\.path)).uniqued().sorted()
    }
}
