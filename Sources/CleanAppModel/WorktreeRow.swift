import CleanCore
import Foundation

/// One row of the Worktrees table: a worktree and its verdict from the last scan, with the texts and sort
/// keys the table shows.
public struct WorktreeRow: Identifiable, Hashable, Sendable {
    /// How a status is drawn: one badge color per group.
    public enum Tone: Sendable, Hashable {
        case autoReady, safe, blocked, inUse
    }

    public let assessment: WorktreeAssessment
    /// Position in the scan (each repo's main checkout first); the last sort key, so ties keep it.
    public let scanOrder: Int

    public init(assessment: WorktreeAssessment, scanOrder: Int) {
        self.assessment = assessment
        self.scanOrder = scanOrder
    }

    public var id: String { assessment.id }
    public var worktree: Worktree { assessment.worktree }
    public var path: String { worktree.path }
    public var url: URL { worktree.url }

    public var repoName: String { DisplayText.repoName(worktree.repoPath) }
    public var branchText: String { DisplayText.branch(of: worktree) }
    public var kind: WorktreeKind { worktree.kind }
    public var kindText: String { worktree.kind.rawValue }
    public var sizeBytes: Int64? { assessment.estimatedBytes }
    public var sizeText: String { DisplayText.bytes(sizeBytes) }
    public var idleDays: Int? { assessment.idle.idleDays }
    public var idleText: String { DisplayText.idle(assessment) }

    public var status: WorktreeStatus { assessment.status }
    /// Exactly what `clean-claude scan` prints in its STATUS column.
    public var statusLabel: String { status.label }

    public var tone: Tone {
        switch status {
        case .autoReady: .autoReady
        case .safe: .safe
        case .blocked: .blocked
        case .inUse: .inUse
        }
    }

    /// The badge word: AUTO-READY, SAFE, BLOCKED or IN USE.
    public var badgeText: String {
        switch status {
        case .autoReady, .safe, .inUse: status.label
        case .blocked: "BLOCKED"
        }
    }

    /// Next to the badge: the blocking reason's label, or the processes (name and pid) for IN USE.
    public var statusDetail: String? {
        switch status {
        case .autoReady, .safe: nil
        case .blocked(let reason): reason.label
        case .inUse: processes.map(\.description).joined(separator: ", ")
        }
    }

    /// The processes that have their working folder inside.
    public var processes: [ProcessCwdIndex.Entry] {
        assessment.safety.blockers.flatMap { reason -> [ProcessCwdIndex.Entry] in
            if case .inUse(let entries) = reason { return entries }
            return []
        }
    }

    /// Every reason, as P2 words them: blockers first, then notes.
    public var reasons: [SafetyReason] { assessment.safety.blockers + assessment.safety.notes }

    /// For the status cell's tooltip: one "label: sentence" line per reason.
    public var reasonsHelp: String {
        guard !reasons.isEmpty else { return "Nothing keeps auto mode away from it." }
        return reasons.map { "\($0.label): \($0.sentence)" }.joined(separator: "\n")
    }

    public var canRemove: Bool { assessment.safety.manualAllowed }
    /// git still lists it but its folder is gone: `git worktree prune` clears the record.
    public var isMissingFolder: Bool { assessment.safety.blockers.contains(.missingFolder) }

    // MARK: - Sort keys (unknown values sort first)

    public var sizeSortKey: Int64 { sizeBytes ?? -1 }
    public var idleSortKey: Int { idleDays ?? -1 }
    public var statusSortKey: Int {
        switch tone {
        case .autoReady: 0
        case .safe: 1
        case .inUse: 2
        case .blocked: 3
        }
    }
}
