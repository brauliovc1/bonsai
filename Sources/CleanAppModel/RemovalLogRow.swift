import CleanCore
import Foundation

/// One row of Recently removed: a `removals.jsonl` entry with the texts the table shows.
public struct RemovalLogRow: Identifiable, Hashable, Sendable {
    public let entry: RemovalLogEntry

    public init(entry: RemovalLogEntry) {
        self.entry = entry
    }

    public var id: UUID { entry.id }
    public var date: Date { entry.date }
    public var path: String { entry.path }

    /// Plain action labels; an action this version has no label for shows its
    /// raw name (no exhaustive switch, so a later phase's new action still compiles).
    public var actionText: String {
        let labels: [RemovalAction: String] = [
            .worktreeRemove: "Removed worktree",
            .worktreeRemoveAnyway: "Removed anyway",
            .worktreePrune: "Cleared missing folders",
            .lightClean: "Cleaned dependencies",
            .derivedDataDelete: "Deleted orphaned DerivedData",
            .dockerPrune: "Cleaned up Docker",
            .simulatorsDeleteUnavailable: "Deleted unavailable simulators",
            .cacheClean: "Cleaned tool cache",
            .movedToTrash: "Moved to Trash",
            .putBack: "Put back from Trash",
            .trashEmptied: "Emptied Trash",
        ]
        let action = labels[entry.action] ?? entry.action.rawValue
        return entry.mode == .auto ? "\(action) (auto)" : action
    }

    /// For a worktree removed anyway (PLAN §4.8): what was lost, in one line ("Lost: 3 uncommitted files.").
    public var lossLine: String? {
        entry.action == .worktreeRemoveAnyway ? entry.notes.first : nil
    }

    /// The kept branch, "detached at 1a2b3c4d", or "–".
    public var branchText: String {
        if let branch = entry.branch { return branch }
        if let sha = entry.headSha { return "detached at \(sha.prefix(8))" }
        return "–"
    }

    /// Measured freed space, or "–".
    public var freedText: String { DisplayText.bytes(entry.freedBytes) }
    public var freedSortKey: Int64 { entry.freedBytes ?? -1 }

    public var isRestorable: Bool { entry.isRestorable }
    public var restoreNote: String {
        switch entry.action {
        case .worktreePrune: "Its folder was already missing; only git's record was cleared."
        case .lightClean: "Run the project's package or build command to get these folders back."
        case .derivedDataDelete: "Xcode builds this folder again when needed."
        case .cacheClean: "The tool downloads or rebuilds this cache when needed."
        case .dockerPrune: "Docker recreates its unused data when needed. This cleanup can't be restored."
        case .simulatorsDeleteUnavailable: "Create a new device in Xcode to use that simulator again."
        case .movedToTrash: "Can be put back while the file remains in the Trash."
        case .putBack: "Returned to its original Downloads location."
        case .trashEmptied: "Finder permanently deleted the Trash contents. These files can't be put back."
        default: "This cleanup can't be restored."
        }
    }
    public var restoredAt: Date? { entry.restoredAt }

    /// For the row's tooltip: the notes the cleanup was accepted with.
    public var notesHelp: String {
        var lines = entry.notes
        if let estimate = entry.estimatedBytes { lines.insert("Estimated size: \(DisplayText.bytes(estimate))", at: 0) }
        return lines.isEmpty ? entry.path : lines.joined(separator: "\n")
    }
}
