import CleanCore

/// The plain sentences behind the words: one per reason for the details panel and the removal sheet, one that
/// explains a row's status, and the one action that fixes it or does it.
extension WorktreeStatusText {
    /// PLAN §8.5, exact copy: why a repo folder is never removed, and what frees space there instead.
    public static let repoFolderSentence = "This is the repo itself. Bonsai only removes extra worktrees; "
        + "use Clean dependencies to free space here."

    /// What the reason means and what to do about it, in the app's words (Bonsai, not the CLI).
    public static func sentence(for reason: SafetyReason) -> String {
        switch reason {
        case .mainCheckout:
            return repoFolderSentence
        case .missingFolder:
            return "The folder is gone, but git still lists it. Pruning clears git's record of it."
        case .locked(let why):
            let because = why.isEmpty ? "" : " (\(why))"
            return "It's locked\(because). Unlock it with git worktree unlock before removing it."
        case .inUse(let processes):
            let names = processes.map(\.description).joined(separator: ", ")
            return "\(names.isEmpty ? "An app" : names) works inside it. Quit it or leave the folder, then refresh."
        case .inUseUnknown:
            return "Bonsai couldn't check which apps work inside (lsof is missing), so auto clean leaves it alone."
        case .uncommitted(let count):
            let files = count == 1 ? "1 file has changes" : "\(count) files have changes"
            return "\(files) that aren't committed and would be lost. Commit or discard them first."
        case .hiddenLocalEdits(let paths):
            return "Some files are marked so git doesn't show their edits: \(list(paths)). Check them first."
        case .operationInProgress(let markers):
            return "\(operationName(markers.first)) is in progress here. Finish or abort it first."
        case .submodules:
            return "It has submodules. git removes those only with --force, which Bonsai never uses."
        case .nestedCheckouts(let paths):
            return "Other git checkouts live inside it and would be deleted with it: \(list(paths))."
        case .nestedClones(let paths):
            return "It holds package clones with no local work, which can be fetched again; they go with it: "
                + "\(list(paths))."
        case .nestedSearchIncomplete(let why):
            return "Bonsai couldn't finish looking for other checkouts inside (\(why)), so one could be missed."
        case .localOnlyCommits(let count, let onBranch):
            let commits = count == 1 ? "1 commit isn't" : "\(count) commits aren't"
            return onBranch
                ? "\(commits) on any remote yet; the branch is kept, so \(count == 1 ? "it stays" : "they stay")."
                : "\(commits) on any branch or remote and would be lost. Create a branch or push first."
        case .reflogOnlyCommits(let count):
            let commits = count == 1 ? "1 commit is" : "\(count) commits are"
            return "\(commits) only in this worktree's history (no branch, tag or remote has them) and would be lost."
        case .stash(let count):
            let stashes = count == 1 ? "1 stash was" : "\(count) stashes were"
            return "\(stashes) made on this branch; stashes belong to the repo and are kept."
        case .ignoredUserFiles(let paths):
            return "Ignored files that aren't build output would be deleted with it: \(list(paths))."
        case .claudeSession:
            return SafetyReason.claudeSessionWarning
        case .recentlyActive(let days):
            return "You worked here \(DisplayText.daysAgo(days).lowercased()), so auto clean waits until it has been idle longer."
        case .idleUnknown:
            return "Bonsai couldn't tell when it was last used, so auto clean leaves it alone."
        case .gitError(let message):
            return "git couldn't read it: \(message)"
        case .staleRecord(let leadsTo):
            return "git's record points at a folder of another repo (its .git leads to \(leadsTo)), "
                + "so Bonsai leaves it alone."
        }
    }

    /// The row's status in one plain sentence.
    public static func explanation(for assessment: WorktreeAssessment) -> String {
        if let attention = assessment.safety.notes.first(where: { words(for: $0).tone == .orange }), assessment.safety.manualAllowed {
            return sentence(for: attention)
        }
        switch assessment.status {
        case .autoReady:
            return "It's pushed and clean, so you can remove it (auto clean would too); its branch is kept."
        case .safe:
            let unpushed = assessment.safety.notes.first { if case .localOnlyCommits = $0 { true } else { false } }
            return unpushed.map(sentence(for:)).map { "You can remove it. " + $0 } ?? "You can remove it; its branch is kept."
        case .blocked(let reason):
            return sentence(for: reason)
        case .inUse:
            return sentence(for: assessment.safety.blockers.first(where: \.isInUse) ?? .inUse([]))
        }
    }

    /// The one action that does the job, or that fixes what stops it.
    public static func fix(for assessment: WorktreeAssessment) -> WorktreeFix {
        switch assessment.status {
        case .autoReady, .safe: .remove
        case .blocked(let reason): fix(for: reason)
        case .inUse: .refresh
        }
    }

    static func fix(for reason: SafetyReason) -> WorktreeFix {
        switch reason {
        case .mainCheckout: .cleanDependencies
        case .missingFolder: .prune
        case .locked, .uncommitted, .hiddenLocalEdits, .operationInProgress, .localOnlyCommits, .reflogOnlyCommits,
             .submodules:
            .openInTerminal
        case .nestedCheckouts: .showInFinder
        case .inUse, .gitError, .nestedSearchIncomplete: .refresh
        case .staleRecord: .none
        // Notes: they never stop a removal by hand.
        case .inUseUnknown, .nestedClones, .stash, .ignoredUserFiles, .claudeSession, .recentlyActive, .idleUnknown:
            .remove
        }
    }

    /// Up to five items, then "and N more".
    private static func list(_ items: [String]) -> String {
        items.prefix(5).joined(separator: ", ") + (items.count > 5 ? " and \(items.count - 5) more" : "")
    }
}
