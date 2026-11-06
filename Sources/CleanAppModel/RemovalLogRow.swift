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

    /// "Removed worktree", "Cleared missing folders"; later phases' actions show their raw name until
    /// they get a label here.
    public var actionText: String {
        let action = entry.action == .worktreeRemove ? "Removed worktree"
            : entry.action == .worktreePrune ? "Cleared missing folders"
            : entry.action.rawValue
        return entry.mode == .auto ? "\(action) (auto)" : action
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
    public var restoredAt: Date? { entry.restoredAt }

    /// For the row's tooltip: the notes the cleanup was accepted with.
    public var notesHelp: String {
        var lines = entry.notes
        if let estimate = entry.estimatedBytes { lines.insert("Estimated size: \(DisplayText.bytes(estimate))", at: 0) }
        return lines.isEmpty ? entry.path : lines.joined(separator: "\n")
    }
}
