import CleanCore
import Foundation

/// The multi-line verdict `remove` prints in a dry run.
enum VerdictText {
    static func describe(_ assessment: WorktreeAssessment, display: PathDisplay) -> String {
        let worktree = assessment.worktree
        let safety = assessment.safety
        var lines: [String] = []
        if worktree.kind == .claude {
            lines.append("warning: \(SafetyReason.claudeSessionWarning)")
        }

        var facts = [worktree.repoURL.lastPathComponent]
        facts.append(worktree.branch.map { "branch \($0)" } ?? "detached at \(worktree.head?.prefix(12) ?? "?")")
        facts.append(worktree.kind.rawValue)
        facts.append(idleText(assessment.idle, isMain: worktree.isMain))
        if let bytes = assessment.estimatedBytes { facts.append("~\(ByteFormatting.string(bytes))") }
        lines.append("\(display.string(worktree.url))  (\(facts.joined(separator: ", ")))")

        let manual = safety.manualAllowed ? "can be removed by hand" : "can't be removed"
        let auto = safety.autoEligible ? "auto mode would remove it" : "auto mode would leave it"
        lines.append("  verdict: \(assessment.status.label): \(manual); \(auto)")
        for reason in safety.blockers {
            lines.append("  blocked: \(reason.sentence)")
        }
        for reason in safety.notes where reason != .claudeSession {
            let autoOnly = safety.autoOnlyBlockers.contains(reason) ? " (keeps auto mode away)" : ""
            lines.append("  note: \(reason.sentence)\(autoOnly)")
        }
        for case .ignoredUserFiles(let paths) in safety.notes where paths.count > 5 {
            lines.append("  ignored files that would be deleted: \(paths.joined(separator: ", "))")
        }

        if safety.manualAllowed {
            lines.append("  would run: git -C \(quoted(worktree.repoPath)) worktree remove \(quoted(worktree.path))")
            let kept = worktree.branch.map { "branch \($0)" } ?? "commit \(worktree.head?.prefix(12) ?? "?") (restore with --detach)"
            lines.append("  kept: \(kept)")
        } else if safety.blockers.contains(.missingFolder) {
            lines.append("  instead: bonsai prune (clears git's record of missing folders)")
        }
        return lines.joined(separator: "\n")
    }

    static func idleText(_ idle: IdleReport, isMain: Bool) -> String {
        if isMain { return "main" }
        guard let days = idle.idleDays else { return idle.capHit ? "idle unknown (too many files)" : "idle unknown" }
        let why = idle.newestSignal.map { " by \($0.label)" } ?? ""
        return "idle \(days)d\(why)"
    }

    /// Quotes a path for display when it has spaces or quotes.
    static func quoted(_ path: String) -> String {
        guard path.contains(where: { $0 == " " || $0 == "'" || $0 == "\"" }) else { return path }
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
