import CleanCore
import Foundation

/// What the Remove anyway sheet asks the person to confirm (PLAN §4.8): one worktree, from a fresh look, with
/// the exact list of what is deleted for good. `Remover.removeAnyway` looks again right before the delete and
/// refuses when anything differs from it.
public struct RemoveAnywayConfirmation: Identifiable, Sendable {
    public let id = UUID()
    /// The fresh look the list was built from.
    public let assessment: WorktreeAssessment
    public let lossList: LossList

    init(assessment: WorktreeAssessment, lossList: LossList) {
        self.assessment = assessment
        self.lossList = lossList
    }

    public var worktree: Worktree { assessment.worktree }
    public var rowID: WorktreeRow.ID { WorktreeRow.ID(worktree) }
    public var title: String { RemoveAnywayText.title(for: worktree) }
    public var line: String { RemoveAnywayText.line(for: worktree) }
    /// What `Remover` checks git's record and the verdict against, besides the list.
    public var expectation: RemovalExpectation { RemovalExpectation(assessment: assessment) }
}

/// What happened after the person confirmed.
public enum RemoveAnywayOutcome: Sendable {
    case removed(RemovalResult)
    /// It changed since the confirmation (each change in a sentence); nothing was deleted.
    case changed([String])
    /// Not removed: another cleanup was running, git refused, or the worktree is gone.
    case failed(String)

    public var removed: Bool {
        if case .removed = self { return true }
        return false
    }

    /// What the sheet says.
    public var text: String {
        switch self {
        case .removed(let result):
            let freed = result.freedBytes.map { " and freed \(DisplayText.bytes($0))" } ?? ""
            let kept = result.entry.branch.map { "Its branch \($0) is kept." } ?? "Its commit is noted in Recently removed."
            let warnings = result.warnings.isEmpty ? "" : " " + result.warnings.joined(separator: " ")
            return "Removed it anyway\(freed). \(kept) Restore in Recently removed brings the worktree back, "
                + "not what was deleted." + warnings
        case .changed:
            return RemoveAnywayText.changed
        case .failed(let why):
            return "Not removed: \(why)."
        }
    }

    /// The changes, for the refusal.
    public var changes: [String] {
        if case .changed(let changes) = self { return changes }
        return []
    }
}
