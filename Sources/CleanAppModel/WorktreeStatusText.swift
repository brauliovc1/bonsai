import CleanCore

/// The words the app uses for a worktree's status (PLAN §8.4), from the same verdict `bonsai scan` prints.
/// `SafetyReason` and the CLI keep their own words; these live only in the app. Pure functions: exhaustive
/// switches, so a new `WorktreeStatus` or `SafetyReason` case doesn't compile until it has words here.
///
/// The chip of a row: green when it can be removed ("Ready · auto clean", "Ready to remove"), or the words of
/// the reason that stops it. A removable worktree whose note needs your attention (ignored files that would be
/// deleted with it) shows that note's orange words instead of green. "Needs attention" = every worktree with an
/// orange reason, also when its chip shows another one first ("Locked" with unsaved changes); those orange reasons
/// are then among the notes next to the chip.
public enum WorktreeStatusText {
    /// The chip for one worktree.
    public static func chip(for assessment: WorktreeAssessment) -> StatusWords {
        switch assessment.status {
        case .autoReady:
            return attentionNote(in: assessment) ?? StatusWords("Ready · auto clean", .green, symbol: "checkmark.circle.fill")
        case .safe:
            return attentionNote(in: assessment) ?? StatusWords("Ready to remove", .green, symbol: "checkmark.circle")
        case .blocked(let reason):
            return words(for: reason)
        case .inUse:
            let inUse = assessment.safety.blockers.first(where: \.isInUse) ?? .inUse([])
            return words(for: inUse)
        }
    }

    /// True for the rows the "Needs attention" filter shows: any of its reasons is orange (local work, other repos
    /// inside, ignored files that would be deleted), whatever the chip shows first.
    public static func needsAttention(_ assessment: WorktreeAssessment) -> Bool {
        reasons(of: assessment).contains { words(for: $0).tone == .orange }
    }

    /// The notes next to the chip, in the verdict's order: orange reasons the chip doesn't already show ("2 unsaved
    /// changes" next to "Locked"), then the quiet notes: "1 commit not pushed" (on a branch, which keeps it),
    /// "2 stashes kept", "Claude session".
    public static func notes(for assessment: WorktreeAssessment) -> [String] {
        let all = reasons(of: assessment).map(words(for:))
        let chipText = chip(for: assessment).text
        let attention = all.filter { $0.tone == .orange && !$0.isNote && $0.text != chipText }.map(\.text)
        return attention + all.filter(\.isNote).map(\.text)
    }

    private static func reasons(of assessment: WorktreeAssessment) -> [SafetyReason] {
        assessment.safety.blockers + assessment.safety.notes
    }

    /// The §8.4 words and color of one reason.
    public static func words(for reason: SafetyReason) -> StatusWords {
        switch reason {
        case .mainCheckout:
            StatusWords("Repo folder", .grey, symbol: "folder")
        case .missingFolder:
            StatusWords("Folder missing", .grey, symbol: "questionmark.folder")
        case .locked:
            StatusWords("Locked", .grey, symbol: "lock")
        case .inUse(let processes):
            StatusWords("Open in \(appNames(processes))", .blue, symbol: "macwindow")
        case .inUseUnknown:
            StatusWords("Maybe in use", .blue, symbol: "questionmark.circle")
        case .uncommitted(let count):
            StatusWords("\(count) unsaved \(count == 1 ? "change" : "changes")", .orange, symbol: "pencil.circle")
        case .hiddenLocalEdits:
            StatusWords("Hidden local edits", .orange, symbol: "eye.slash")
        case .operationInProgress(let markers):
            StatusWords("\(operationName(markers.first)) in progress", .orange, symbol: "arrow.triangle.pull")
        case .submodules:
            StatusWords("Has submodules", .grey, symbol: "shippingbox")
        case .nestedCheckouts:
            StatusWords("Contains other repos", .orange, symbol: "folder.badge.questionmark")
        case .nestedClones:
            // Clones with no local work are a note in both modes (§4.1): grey, so a SwiftPM worktree with its
            // .build/checkouts isn't put under "Needs attention" (or an auto-ready one colored orange).
            StatusWords("Contains other repos", .grey, symbol: "folder")
        case .nestedUnreadable(let repos):
            StatusWords("Couldn't read \(repos.count) \(repos.count == 1 ? "repo" : "repos") inside", .orange,
                        symbol: "exclamationmark.triangle")
        case .packageCopies(let paths):
            // Build output (§4.1): shown in the details only, never next to the chip.
            StatusWords("Package copies (\(paths.count))", .grey, symbol: "shippingbox")
        case .nestedSearchIncomplete, .gitError, .staleRecord:
            StatusWords("Couldn't check", .grey, symbol: "exclamationmark.circle")
        case .localOnlyCommits(let count, let onBranch):
            onBranch
                ? StatusWords(commitsNotPushed(count), .grey, isNote: true)
                : StatusWords(commitsNotPushed(count), .orange, symbol: "arrow.up.circle")
        case .reflogOnlyCommits:
            StatusWords("Unreachable commits", .orange, symbol: "arrow.uturn.backward.circle")
        case .stash(let count):
            StatusWords("\(count) \(count == 1 ? "stash" : "stashes") kept", .grey, isNote: true)
        case .ignoredUserFiles:
            StatusWords("Has ignored files", .orange, symbol: "doc.badge.ellipsis")
        case .claudeSession:
            StatusWords("Claude session", .grey, isNote: true)
        case .recentlyActive(let days):
            StatusWords("Active \(DisplayText.daysAgo(days).lowercased())", .grey, symbol: "clock")
        case .idleUnknown:
            StatusWords("Activity unknown", .grey, symbol: "clock")
        }
    }

    /// A note that needs your attention although the worktree can be removed (orange, not a quiet note).
    private static func attentionNote(in assessment: WorktreeAssessment) -> StatusWords? {
        assessment.safety.notes.map(words(for:)).first { $0.tone == .orange && !$0.isNote }
    }

    private static func commitsNotPushed(_ count: Int) -> String {
        "\(count) \(count == 1 ? "commit" : "commits") not pushed"
    }

    /// "node", "node, zsh", "node, zsh +1": the apps working inside, each once.
    static func appNames(_ processes: [ProcessCwdIndex.Entry]) -> String {
        var names: [String] = []
        for process in processes where !names.contains(process.command) { names.append(process.command) }
        guard !names.isEmpty else { return "another app" }
        let shown = names.prefix(2).joined(separator: ", ")
        return names.count > 2 ? "\(shown) +\(names.count - 2)" : shown
    }

    /// "Rebase", "Merge", "Cherry-pick", "Revert", "Bisect" from the marker git leaves in its folder.
    static func operationName(_ marker: String?) -> String {
        switch marker {
        case "rebase-merge", "rebase-apply": "Rebase"
        case "MERGE_HEAD": "Merge"
        case "CHERRY_PICK_HEAD": "Cherry-pick"
        case "REVERT_HEAD": "Revert"
        case "BISECT_LOG": "Bisect"
        default: "A git operation"
        }
    }
}
