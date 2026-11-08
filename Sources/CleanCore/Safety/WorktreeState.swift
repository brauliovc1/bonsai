/// What `WorktreeInspector` read from git and the disk for one worktree: the facts the §4.1 checks need.
public struct WorktreeState: Sendable, Hashable {
    public var folderExists: Bool
    /// Entries of `git status --porcelain=v1 -z --untracked-files=all`.
    public var changedFiles: Int
    /// `assume-unchanged` / `skip-worktree` files present on disk: edits `git status` never shows.
    public var hiddenEdits: [String]
    /// Markers of a half-done rebase, merge, cherry-pick, revert or bisect in the worktree's git dir.
    public var operationsInProgress: [String]
    /// `.gitmodules` is present.
    public var hasSubmodules: Bool
    /// `git rev-list --count HEAD --not --remotes`.
    public var localOnlyCommits: Int
    /// Detached only: commits named in the worktree's own `logs/HEAD` that no branch, tag or remote reaches.
    public var reflogOnlyCommits: Int
    /// Stash entries made on this worktree's branch (0 when detached).
    public var branchStashes: Int
    /// Ignored files and folders that are not regenerable (§4.2), relative to the worktree.
    public var ignoredUserFiles: [String]
    /// Other git checkouts inside this one that may hold work: registered worktrees, `.git` files, and
    /// clones with local work. `git worktree remove` would delete them along with it.
    public var nestedCheckouts: [String]
    /// Nested clones with no local work (package managers' checkouts): deleted with the worktree, fetched again
    /// when needed. Shown, never blocking.
    public var nestedClones: [String]
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
        hiddenEdits: [String] = [],
        operationsInProgress: [String] = [],
        hasSubmodules: Bool = false,
        localOnlyCommits: Int = 0,
        reflogOnlyCommits: Int = 0,
        branchStashes: Int = 0,
        ignoredUserFiles: [String] = [],
        nestedCheckouts: [String] = [],
        nestedClones: [String] = [],
        nestedSearchIncomplete: String? = nil,
        gitErrors: [String] = [],
        staleRecord: String? = nil
    ) {
        self.folderExists = folderExists
        self.changedFiles = changedFiles
        self.hiddenEdits = hiddenEdits
        self.operationsInProgress = operationsInProgress
        self.hasSubmodules = hasSubmodules
        self.localOnlyCommits = localOnlyCommits
        self.reflogOnlyCommits = reflogOnlyCommits
        self.branchStashes = branchStashes
        self.ignoredUserFiles = ignoredUserFiles
        self.nestedCheckouts = nestedCheckouts
        self.nestedClones = nestedClones
        self.nestedSearchIncomplete = nestedSearchIncomplete
        self.gitErrors = gitErrors
        self.staleRecord = staleRecord
    }

    public static let missing = WorktreeState(folderExists: false)
}
