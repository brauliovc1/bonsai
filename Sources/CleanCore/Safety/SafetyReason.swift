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
    /// Clones with no local work inside: a note in both modes.
    case nestedClones([String])
    /// Repos inside that git couldn't read, each with git's first error line (PLAN §4.1, added 11-09): what
    /// they hold is unknown, so they block both modes.
    case nestedUnreadable([NestedRepo])
    /// Package managers' copies inside ignored build folders (PLAN §4.1 "Package copies", 11-09): build
    /// output, a note in both modes.
    case packageCopies([String])
    case nestedSearchIncomplete(String)
    case localOnlyCommits(count: Int, onBranch: Bool)
    case reflogOnlyCommits(count: Int)
    case stash(count: Int)
    case ignoredUserFiles([String])
    case claudeSession
    case recentlyActive(days: Int)
    case idleUnknown
    case gitError(String)
    /// git's record of this worktree belongs to another repo's folder: the folder's `.git` file leads to the
    /// git dir given here, not to a record of this repo. Every fact read in the folder would describe the
    /// other repo's worktree, so nothing about it can be trusted (blocks both modes).
    case staleRecord(leadsTo: String)

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
        case .nestedClones(let paths): "package clones (\(paths.count))"
        case .nestedUnreadable(let repos): "unreadable nested repos (\(repos.count))"
        case .packageCopies(let paths): "package copies (\(paths.count))"
        case .nestedSearchIncomplete: "nested search incomplete"
        case .localOnlyCommits(let count, _): "local-only commits (\(count))"
        case .reflogOnlyCommits(let count): "reflog-only commits (\(count))"
        case .stash(let count): "stash (\(count))"
        case .ignoredUserFiles(let paths): "ignored files (\(paths.count))"
        case .claudeSession: "Claude session"
        case .recentlyActive(let days): "active \(days)d ago"
        case .idleUnknown: "idle unknown"
        case .gitError: "git error"
        case .staleRecord: "stale record"
        }
    }

    /// One plain sentence for the UI and the CLI.
    public var sentence: String {
        switch self {
        case .mainCheckout:
            return "This is the repo's main checkout; Bonsai never removes it."
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
        case .nestedClones(let paths):
            return "Clones with no local work (package checkouts that can be fetched again) are inside and go with it: "
                + Self.list(paths) + "."
        case .nestedUnreadable(let repos):
            return "git couldn't read other repos inside it, so what they hold is unknown: "
                + Self.list(repos.map(\.description)) + "."
        case .packageCopies(let paths):
            return "Package copies (Xcode or SwiftPM fetch them again) are inside and go with it: "
                + Self.list(paths) + "."
        case .nestedSearchIncomplete(let why):
            return "The search for other checkouts inside could not finish (\(why)), so one could be missed."
        case .reflogOnlyCommits(let count):
            return "\(count) \(count == 1 ? "commit is" : "commits are") only in this worktree's HEAD reflog "
                + "(no branch, tag or remote has them); removing it would lose them."
        case .submodules:
            return "It has submodules; git removes those only with --force, which Bonsai never uses."
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
        case .staleRecord(let leadsTo):
            return "This record belongs to another repo's folder: the folder's .git file leads to \(leadsTo), "
                + "not to a record of this repo, so everything read there would describe someone else's "
                + "worktree. It is left alone, by hand and in auto mode."
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
