/// PLAN §4.8 "Remove anyway": which blocked worktrees it is offered for, and the one function that builds the
/// loss list from an inspection (the scan's, the confirmation's fresh look, and the re-check right before the
/// delete all call it).
///
/// Offered only when every blocker is one whose loss can be listed exactly: uncommitted or untracked files,
/// hidden local edits, repos inside with local work or that git couldn't read, submodules, commits on no remote
/// while detached, detached reflog-only commits. Never for a repo folder, a missing folder, a locked worktree,
/// one in use or maybe in use, an operation in progress, a git error or stale record on the worktree itself, or
/// another registered worktree (or `.git` file) inside it; nor when the search for repos inside couldn't finish,
/// since the list could then miss one.
public enum RemoveAnyway {
    public enum Verdict: Sendable, Hashable {
        /// A removal by hand accepts it: plain Remove does the job.
        case notNeeded
        /// Blocked only by what the list holds exactly.
        case offered(LossList)
        /// The first blocker Remove anyway never overrides, or why the list can't be exact.
        case unavailable(SafetyReason)

        public var lossList: LossList? {
            if case .offered(let list) = self { return list }
            return nil
        }
    }

    /// `state`: the inspection the verdict was made from; nil when none was made (nothing can be listed).
    public static func verdict(for worktree: Worktree, state: WorktreeState?, safety: SafetyReport) -> Verdict {
        if safety.manualAllowed { return .notNeeded }
        for reason in safety.blockers + safety.notes where !isOverridable(reason, isBlocker: safety.blockers.contains(reason)) {
            return .unavailable(reason)
        }
        guard let state, state.folderExists else { return .unavailable(.gitError("what it holds was not read")) }
        if !state.nestedWorktrees.isEmpty { return .unavailable(.nestedCheckouts(state.nestedWorktrees)) }
        if state.changedPaths.count != state.changedFiles {
            return .unavailable(.gitError("git status could not be listed path by path"))
        }
        if state.hasSubmodules, state.submodulePaths == nil { return .unavailable(.gitError(".gitmodules could not be read")) }
        if worktree.isDetached, state.localOnlyShas.count != state.localOnlyCommits {
            return .unavailable(.gitError("the commits on no remote could not be listed"))
        }
        if state.reflogOnlyShas.count != state.reflogOnlyCommits {
            return .unavailable(.gitError("the reflog-only commits could not be listed"))
        }
        return .offered(lossList(for: worktree, state: state))
    }

    /// Whether Remove anyway may delete what `reason` stands for. Notes (which don't block a removal by hand)
    /// are fine, except the two that make the list unsure: maybe in use, and an incomplete search.
    public static func isOverridable(_ reason: SafetyReason, isBlocker: Bool) -> Bool {
        switch reason {
        case .uncommitted, .hiddenLocalEdits, .nestedUnreadable, .submodules, .reflogOnlyCommits:
            true
        // Registered worktrees inside are told apart by the state (`nestedWorktrees`).
        case .nestedCheckouts:
            true
        case .localOnlyCommits(_, let onBranch):
            isBlocker ? !onBranch : true
        case .mainCheckout, .missingFolder, .locked, .inUse, .inUseUnknown, .operationInProgress, .gitError,
             .staleRecord, .nestedSearchIncomplete:
            false
        case .nestedClones, .packageCopies, .stash, .ignoredUserFiles, .claudeSession, .recentlyActive, .idleUnknown:
            !isBlocker
        }
    }

    /// Every category of §4.8, from the state's exact entries.
    static func lossList(for worktree: Worktree, state: WorktreeState) -> LossList {
        let stamp = { (path: String) in state.pathStamps[path] }
        var sections: [LossList.Section] = []
        func add(_ category: LossList.Category, _ entries: [LossList.Entry]) {
            sections.append(LossList.Section(category: category, entries: entries))
        }
        add(.uncommittedFiles, state.changedPaths.map { entry in
            LossList.Entry(text: entry.path, detail: statusWord(entry), key: entry.code, stamp: stamp(entry.path))
        })
        add(.hiddenEdits, state.hiddenEdits.map { LossList.Entry(text: $0, stamp: stamp($0)) })
        add(.reposWithLocalWork, state.nestedLocalWork.map { LossList.Entry(text: $0.path, detail: $0.findings.joined(separator: ", ")) })
        add(.unreadableRepos, state.nestedUnreadable.map { LossList.Entry(text: $0.path, detail: $0.findings.joined(separator: ", ")) })
        if state.hasSubmodules {
            let paths = state.submodulePaths ?? []
            add(.submodules, paths.isEmpty ? [LossList.Entry(text: ".gitmodules", detail: "names no submodule path")]
                : paths.map { LossList.Entry(text: $0) })
        }
        if worktree.isDetached {
            add(.unpushedCommits, state.localOnlyShas.map(commit))
        }
        add(.unreachableCommits, state.reflogOnlyShas.map(commit))
        add(.ignoredFiles, state.ignoredUserFiles.map { LossList.Entry(text: $0, stamp: stamp($0)) })
        if !worktree.isDetached, state.localOnlyCommits > 0 {
            add(.commitsOnBranch, [LossList.Entry(text: LossList.Category.commitsOnBranch.counted(state.localOnlyCommits)
                + " on " + (worktree.branch ?? "its branch"))])
        }
        if state.branchStashes > 0 {
            add(.stashes, [LossList.Entry(text: LossList.Category.stashes.counted(state.branchStashes) + " made on this branch")])
        }
        if worktree.kind == .claude {
            add(.claudeSession, [LossList.Entry(text: SafetyReason.claudeSessionWarning)])
        }
        return LossList(sections: sections)
    }

    private static func commit(_ sha: String) -> LossList.Entry {
        LossList.Entry(text: String(sha.prefix(12)), key: sha)
    }

    /// git's two status letters in a word: "untracked", "modified", "renamed from old.txt".
    static func statusWord(_ entry: GitStatusEntry) -> String {
        let letters = Array(entry.code)
        let index = letters.first ?? " "
        let tree = letters.count > 1 ? letters[1] : " "
        if entry.code == "??" { return "untracked" }
        if entry.code == "!!" { return "ignored" }
        if letters.contains("U") || entry.code == "AA" || entry.code == "DD" { return "conflict" }
        if index == "R" { return "renamed from " + (entry.from ?? "?") }
        if index == "C" { return "copied from " + (entry.from ?? "?") }
        if index == "D" || tree == "D" { return "deleted" }
        if index == "A" { return tree == " " ? "added" : "added, then changed" }
        if index != " " && tree != " " { return "staged, then changed" }
        return index != " " ? "staged" : "changed"
    }
}
