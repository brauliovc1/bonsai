import CleanCore
import Foundation
import Observation

/// Recently removed: the cleanup log newest first, and Restore through `Restorer`.
@MainActor
@Observable
public final class RemovalsModel {
    /// The outcome of the last restore, for the screen to show.
    public struct Message: Sendable, Hashable {
        public var text: String
        public var isError: Bool
    }

    public let app: AppModel
    public var selection: Set<RemovalLogRow.ID> = []
    public private(set) var restoringID: UUID?
    public var message: Message?

    public init(app: AppModel) {
        self.app = app
    }

    /// Newest first; entries with the same date keep the later-written one first.
    public var rows: [RemovalLogRow] {
        app.logEntries.enumerated()
            .sorted { ($0.element.date, $0.offset) > ($1.element.date, $1.offset) }
            .map { RemovalLogRow(entry: $0.element) }
    }

    public var logError: String? { app.logError }

    /// Puts a removed worktree back with `git worktree add` from its kept branch (or commit), then
    /// rescans. Dependencies are not reinstalled, and the message says so.
    @discardableResult
    public func restore(_ id: RemovalLogRow.ID) async -> Message {
        guard restoringID == nil else { return Message(text: "A restore is already running.", isError: true) }
        guard let git = app.git else { return show(Message(text: "Could not restore: git not found.", isError: true)) }
        restoringID = id
        let restorer = Restorer(git: git, environment: app.environment)
        let message = await app.cleaningUp { await Self.restore(id, with: restorer) }
            ?? Message(text: "Could not restore: \(app.busyReason).", isError: true)
        restoringID = nil
        show(message)
        await app.cleanupFinished()
        return message
    }

    static func restore(_ id: UUID, with restorer: Restorer) async -> Message {
        do {
            let result = try await restorer.restore(entryID: id)
            let ref = result.entry.branch.map { "branch \($0)" } ?? "commit \(result.ref.prefix(12))"
            let text = (["Restored \(result.path) at \(ref).", result.note] + result.warnings).joined(separator: " ")
            return Message(text: text, isError: !result.warnings.isEmpty)
        } catch {
            return Message(text: "Could not restore: \(error)", isError: true)
        }
    }

    @discardableResult
    private func show(_ message: Message) -> Message {
        self.message = message
        return message
    }
}
