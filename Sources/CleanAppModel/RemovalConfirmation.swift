import CleanCore
import Foundation

/// What the removal sheet asks the user to confirm: every selected worktree, allowed or blocked, from the
/// last scan's verdicts. Blocked items are listed with their reasons and never removed. `Remover` checks
/// every allowed item again right before it runs.
public struct RemovalConfirmation: Identifiable, Sendable {
    public static let keptLine = "Branches are kept. You can restore from Recently removed."

    public struct Item: Identifiable, Sendable, Hashable {
        public let assessment: WorktreeAssessment

        public init(assessment: WorktreeAssessment) {
            self.assessment = assessment
        }

        public var id: WorktreeRow.ID { WorktreeRow.ID(assessment.worktree) }
        public var worktree: Worktree { assessment.worktree }
        public var repoName: String { DisplayText.repoName(worktree.repoPath) }
        public var branchText: String { DisplayText.branch(of: worktree) }
        public var estimatedBytes: Int64? { assessment.estimatedBytes }
        public var isAllowed: Bool { assessment.safety.manualAllowed }
        /// What `Remover` checks the fresh state against right before removing.
        public var expectation: RemovalExpectation { RemovalExpectation(assessment: assessment) }

        /// Why it can't be removed (empty when allowed).
        public var blockers: [SafetyReason] { assessment.safety.blockers }

        /// What to know before removing it, as P2 words it. The Claude session note and the ignored files are
        /// left out here: `claudeWarning` and `ignoredUserFiles` show them in full.
        public var notes: [SafetyReason] {
            assessment.safety.notes.filter { note in
                if case .ignoredUserFiles = note { return false }
                return note != .claudeSession
            }
        }

        /// `SafetyReason.claudeSessionWarning` for a Claude-app worktree.
        public var claudeWarning: String? {
            worktree.kind == .claude ? SafetyReason.claudeSessionWarning : nil
        }

        /// Ignored files that are not build output; they are deleted with the folder.
        public var ignoredUserFiles: [String] {
            assessment.safety.notes.flatMap { note -> [String] in
                if case .ignoredUserFiles(let paths) = note { return paths }
                return []
            }
        }
    }

    public let id = UUID()
    public let items: [Item]

    public init(items: [Item]) {
        self.items = items
    }

    public var allowed: [Item] { items.filter(\.isAllowed) }
    public var blocked: [Item] { items.filter { !$0.isAllowed } }

    /// The `du` estimate of the allowed items. Freed space is measured afterwards and can be lower.
    public var estimatedTotalBytes: Int64 { allowed.compactMap(\.estimatedBytes).reduce(0, +) }
    public var estimatedSizeText: String { CleanupPresentation.estimate(allowed.map(\.estimatedBytes)) }
    public var hasUnknownSizes: Bool { allowed.contains { $0.estimatedBytes == nil } }

    /// "Remove 3 worktrees".
    public var removeButtonTitle: String { CleanupPresentation.button("Remove", count: allowed.count) }
    public var title: String { CleanupPresentation.title("Remove", count: allowed.count, noun: "worktree", sizes: allowed.map(\.estimatedBytes)) }

}
