/// Why light clean leaves a folder alone (PLAN §4.2, plus the nested-checkout rule of §4.1 added 11-06).
public enum LightCleanSkipReason: Sendable, Hashable, Codable {
    /// `git check-ignore` says git does not ignore it.
    case notIgnored
    /// `git ls-files` lists files inside it.
    case hasTrackedFiles
    /// The worktree's `git status` lists these paths inside it (edited, untracked or staged files).
    case uncommittedFiles([String])
    case symlink
    /// Other checkouts inside (relative to the folder; `.` = the folder itself is one): a `.git` file, a
    /// registered worktree, or a clone with local work.
    case nestedCheckout([String])
    /// The search for checkouts inside hit its entry cap or an unreadable folder.
    case nestedSearchIncomplete(String)
    case gitError(String)
    /// Not there any more, or no longer a folder.
    case gone
    /// Not a folder this worktree's light clean may touch: found in another worktree, a name outside the
    /// list, or a symlinked folder on the way down.
    case notACandidate(String)
    /// A process has its working folder inside the worktree (`LightCleaner` only).
    case inUse([ProcessCwdIndex.Entry])
    /// Running processes could not be checked (`LightCleaner` only).
    case inUseUnknown(String)

    /// Short, for table cells.
    public var label: String {
        switch self {
        case .notIgnored: "not ignored"
        case .hasTrackedFiles: "tracked files"
        case .uncommittedFiles(let paths): "uncommitted files (\(paths.count))"
        case .symlink: "symlink"
        case .nestedCheckout(let paths): "nested checkout (\(paths.count))"
        case .nestedSearchIncomplete: "nested search incomplete"
        case .gitError: "git error"
        case .gone: "gone"
        case .notACandidate: "not a candidate"
        case .inUse(let processes): "in use (\(processes.map(\.command).uniqued().joined(separator: ", ")))"
        case .inUseUnknown: "in use: unknown"
        }
    }

    /// One plain sentence.
    public var sentence: String {
        switch self {
        case .notIgnored:
            return "git does not ignore it, so it may hold project files."
        case .hasTrackedFiles:
            return "git tracks files inside it."
        case .uncommittedFiles(let paths):
            return "git status lists files inside it that would be lost: \(Self.list(paths))."
        case .symlink:
            return "It is a symbolic link; light clean never follows or deletes links."
        case .nestedCheckout(let paths):
            return "Another git checkout is inside and would be deleted with it: \(Self.list(paths))."
        case .nestedSearchIncomplete(let why):
            return "The search for other checkouts inside could not finish (\(why)), so one could be missed."
        case .gitError(let message):
            return "git failed: \(message)"
        case .gone:
            return "It no longer exists or is no longer a folder."
        case .notACandidate(let why):
            return "It is not a light-clean folder of this worktree: \(why)."
        case .inUse(let processes):
            return "A running process has its working folder inside the worktree: \(Self.list(processes.map(\.description)))."
        case .inUseUnknown(let why):
            return "Running processes could not be checked (\(why))."
        }
    }

    /// Up to five items, then "and N more".
    private static func list(_ items: [String]) -> String {
        items.prefix(5).joined(separator: ", ") + (items.count > 5 ? " and \(items.count - 5) more" : "")
    }
}
