import Foundation

/// Why a worktree can't be removed, or what to know before removing it (PLAN §4.1).
public enum SafetyReason: Sendable, Hashable, Codable {
    case mainCheckout
    case missingFolder
    case locked(reason: String)
    case inUse([ProcessCwdIndex.Entry])
    case inUseUnknown
    case uncommitted(count: Int)
    case hiddenLocalEdits([String])
    case operationInProgress([String])
    case submodules
    /// Other git checkouts inside the folder; `git worktree remove` would delete them too.
    case nestedCheckouts([String])
    case nestedSearchIncomplete(String)
    case localOnlyCommits(count: Int, onBranch: Bool)
    case reflogOnlyCommits(count: Int)
    case stash(count: Int)
    case ignoredUserFiles([String])
    case claudeSession
    case recentlyActive(days: Int)
    case idleUnknown
    case gitError(String)

    /// PLAN §4.1, exact copy.
    public static let claudeSessionWarning = "This worktree belongs to a Claude session. Removing it deletes "
        + "the session's folder, so that session can't continue where it left off. The branch is kept."

    /// Short, for table cells: "uncommitted (31)".
    public var label: String {
        switch self {
        case .mainCheckout: "main checkout"
        case .missingFolder: "folder missing"
        case .locked: "locked"
        case .inUse(let processes): "in use (\(processes.map(\.command).uniqued().joined(separator: ", ")))"
        case .inUseUnknown: "in use: unknown"
        case .uncommitted(let count): "uncommitted (\(count))"
        case .hiddenLocalEdits(let paths): "hidden edits (\(paths.count))"
        case .operationInProgress(let markers): "\(Self.operationName(markers.first ?? "")) in progress"
        case .submodules: "submodules"
        case .nestedCheckouts(let paths): "nested checkouts (\(paths.count))"
        case .nestedSearchIncomplete: "nested search incomplete"
        case .localOnlyCommits(let count, _): "local-only commits (\(count))"
        case .reflogOnlyCommits(let count): "reflog-only commits (\(count))"
        case .stash(let count): "stash (\(count))"
        case .ignoredUserFiles(let paths): "ignored files (\(paths.count))"
        case .claudeSession: "Claude session"
        case .recentlyActive(let days): "active \(days)d ago"
        case .idleUnknown: "idle unknown"
        case .gitError: "git error"
        }
    }

    /// One plain sentence for the UI and the CLI.
    public var sentence: String {
        switch self {
        case .mainCheckout:
            return "This is the repo's main checkout; clean-claude never removes it."
        case .missingFolder:
            return "The folder no longer exists; use prune to clear git's record of it instead."
        case .locked(let reason):
            let why = reason.isEmpty ? "" : " (\(reason))"
            return "The worktree is locked\(why); unlock it with `git worktree unlock` first."
        case .inUse(let processes):
            let names = processes.map(\.description).joined(separator: ", ")
            return "A running process has its working folder inside: \(names)."
        case .inUseUnknown:
            return "Running processes could not be checked (lsof unavailable), so auto mode leaves it alone."
        case .uncommitted(let count):
            return "\(count) uncommitted or untracked \(count == 1 ? "file" : "files") would be lost."
        case .hiddenLocalEdits(let paths):
            return "Files marked assume-unchanged or skip-worktree may hold edits git status doesn't show: "
                + Self.list(paths) + "."
        case .operationInProgress(let markers):
            return "A \(Self.operationName(markers.first ?? "")) is in progress (\(markers.joined(separator: ", ")) "
                + "in its git dir); finish or abort it first."
        case .nestedSearchIncomplete(let why):
            return "The search for other checkouts inside could not finish (\(why)), so one could be missed."
        case .reflogOnlyCommits(let count):
            return "\(count) \(count == 1 ? "commit is" : "commits are") only in this worktree's HEAD reflog "
                + "(no branch, tag or remote has them); removing it would lose them."
        case .submodules:
            return "It has submodules; git removes those only with --force, which clean-claude never uses."
        case .nestedCheckouts(let paths):
            return "Other git checkouts live inside it and would be deleted with it: \(Self.list(paths))."
        case .localOnlyCommits(let count, let onBranch):
            let commits = count == 1 ? "1 commit is" : "\(count) commits are"
            return onBranch
                ? "\(commits) on no remote; the kept branch still holds them."
                : "\(commits) on no remote and no branch holds them (detached HEAD), so removing would lose them."
        case .stash(let count):
            return "\(count) stash \(count == 1 ? "entry was" : "entries were") made on this branch; "
                + "stashes are repo-wide and survive removal."
        case .ignoredUserFiles(let paths):
            return "Ignored files that are not build output would be deleted: \(Self.list(paths))."
        case .claudeSession:
            return Self.claudeSessionWarning
        case .recentlyActive(let days):
            return "Last activity was \(days) \(days == 1 ? "day" : "days") ago, more recently than the idle threshold."
        case .idleUnknown:
            return "When it was last used could not be worked out, so auto mode leaves it alone."
        case .gitError(let message):
            return "git failed: \(message)"
        }
    }

    /// Up to five items, then "and N more".
    private static func list(_ items: [String]) -> String {
        items.prefix(5).joined(separator: ", ") + (items.count > 5 ? " and \(items.count - 5) more" : "")
    }

    private static func operationName(_ marker: String) -> String {
        switch marker {
        case "rebase-merge", "rebase-apply": "rebase"
        case "MERGE_HEAD": "merge"
        case "CHERRY_PICK_HEAD": "cherry-pick"
        case "REVERT_HEAD": "revert"
        case "BISECT_LOG": "bisect"
        default: "git operation"
        }
    }

    /// The worktree holds work that exists nowhere else; auto mode notifies instead of removing.
    public var isLocalWork: Bool {
        switch self {
        case .uncommitted, .hiddenLocalEdits, .operationInProgress, .localOnlyCommits, .reflogOnlyCommits, .stash,
             .ignoredUserFiles: true
        default: false
        }
    }

    public var isInUse: Bool {
        if case .inUse = self { return true }
        return false
    }
}

extension Array where Element: Hashable {
    /// The elements in order, without repeats.
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
