/// What `WorktreeInspector` read from git and the disk for one worktree: the facts the §4.1 checks need.
public struct WorktreeState: Sendable, Hashable {
    public var folderExists: Bool
    /// Entries of `git status --porcelain=v1 -z --untracked-files=all`.
    public var changedFiles: Int
    /// `.gitmodules` is present.
    public var hasSubmodules: Bool
    /// `git rev-list --count HEAD --not --remotes`.
    public var localOnlyCommits: Int
    /// Stash entries made on this worktree's branch (0 when detached).
    public var branchStashes: Int
    /// Ignored files and folders that are not regenerable (§4.2), relative to the worktree.
    public var ignoredUserFiles: [String]
    /// Other git checkouts (registered worktrees or folders with their own `.git`) inside this one.
    /// `git worktree remove` would delete them along with it.
    public var nestedCheckouts: [String]
    /// Every git command that failed. Any error blocks removal.
    public var gitErrors: [String]

    public init(
        folderExists: Bool = true,
        changedFiles: Int = 0,
        hasSubmodules: Bool = false,
        localOnlyCommits: Int = 0,
        branchStashes: Int = 0,
        ignoredUserFiles: [String] = [],
        nestedCheckouts: [String] = [],
        gitErrors: [String] = []
    ) {
        self.folderExists = folderExists
        self.changedFiles = changedFiles
        self.hasSubmodules = hasSubmodules
        self.localOnlyCommits = localOnlyCommits
        self.branchStashes = branchStashes
        self.ignoredUserFiles = ignoredUserFiles
        self.nestedCheckouts = nestedCheckouts
        self.gitErrors = gitErrors
    }

    public static let missing = WorktreeState(folderExists: false)
}
