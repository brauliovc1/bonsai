import Foundation

/// How long a worktree has been idle, and why (PLAN §4.3).
public struct IdleReport: Sendable, Hashable {
    /// The newest of `signals`.
    public var newest: Date?
    /// Whole days since `newest`; nil = idle unknown (file walk capped, a git error, or no signal at all).
    public var idleDays: Int?
    /// Each signal that was found, kept apart so the UI can say why something counts as active.
    public var signals: [IdleSignal: Date]
    /// The file walk stopped at its entry cap before finishing.
    public var capHit: Bool
    /// Signals that could not be read (git failures, unreadable folders).
    public var errors: [String]

    public init(
        newest: Date? = nil,
        idleDays: Int? = nil,
        signals: [IdleSignal: Date] = [:],
        capHit: Bool = false,
        errors: [String] = []
    ) {
        self.newest = newest
        self.idleDays = idleDays
        self.signals = signals
        self.capHit = capHit
        self.errors = errors
    }

    /// Builds a report from the signals found. `idleDays` = floor((now - newest) / 86400), never negative;
    /// nil when the cap was hit, any signal failed, or there is no signal.
    public static func make(
        signals: [IdleSignal: Date],
        capHit: Bool,
        errors: [String],
        now: Date
    ) -> IdleReport {
        let newest = signals.values.max()
        var idleDays: Int?
        if let newest, !capHit, errors.isEmpty {
            idleDays = max(0, Int((now.timeIntervalSince(newest) / 86_400).rounded(.down)))
        }
        return IdleReport(newest: newest, idleDays: idleDays, signals: signals, capHit: capHit, errors: errors)
    }

    /// The signal that set `newest`.
    public var newestSignal: IdleSignal? {
        guard let newest else { return nil }
        return IdleSignal.allCases.first { signals[$0] == newest }
    }

    /// For tests and callers that already know the answer.
    public static func idle(days: Int, now: Date = Date()) -> IdleReport {
        let date = now.addingTimeInterval(-TimeInterval(days) * 86_400)
        return IdleReport(newest: date, idleDays: days, signals: [.headCommit: date])
    }

    /// Idle unknown.
    public static let unknown = IdleReport()
}
