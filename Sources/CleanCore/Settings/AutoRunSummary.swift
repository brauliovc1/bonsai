import Foundation

/// What the last auto-mode run did, kept in `settings.json`.
public struct AutoRunSummary: Sendable, Codable, Equatable {
    public var date: Date
    /// The run was inside the report-only window and removed nothing.
    public var reportOnly: Bool
    public var removedCount: Int
    /// Measured from the volume, not added up from estimates.
    public var freedBytes: Int64
    /// Worktrees idle past the threshold that were kept because they hold local work.
    public var notifiedCount: Int
    /// One line per worktree that could not be removed (git or something unexpected went wrong).
    public var failures: [String]
    /// One line per worktree the last check before its removal left alone, with why: it changed since the
    /// plan, the safety re-check said no, or the run was stopped.
    public var refused: [String]
    /// How many worktrees the plan would remove; in a report-only run, what it would have removed.
    public var plannedCount: Int
    /// The `du` estimate of the planned worktrees.
    public var estimatedBytes: Int64

    public init(
        date: Date,
        reportOnly: Bool,
        removedCount: Int = 0,
        freedBytes: Int64 = 0,
        notifiedCount: Int = 0,
        failures: [String] = [],
        refused: [String] = [],
        plannedCount: Int = 0,
        estimatedBytes: Int64 = 0
    ) {
        self.date = date
        self.reportOnly = reportOnly
        self.removedCount = removedCount
        self.freedBytes = freedBytes
        self.notifiedCount = notifiedCount
        self.failures = failures
        self.refused = refused
        self.plannedCount = plannedCount
        self.estimatedBytes = estimatedBytes
    }

    private enum CodingKeys: String, CodingKey {
        case date, reportOnly, removedCount, freedBytes, notifiedCount, failures, refused, plannedCount, estimatedBytes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? .distantPast
        reportOnly = try container.decodeIfPresent(Bool.self, forKey: .reportOnly) ?? true
        removedCount = try container.decodeIfPresent(Int.self, forKey: .removedCount) ?? 0
        freedBytes = try container.decodeIfPresent(Int64.self, forKey: .freedBytes) ?? 0
        notifiedCount = try container.decodeIfPresent(Int.self, forKey: .notifiedCount) ?? 0
        failures = try container.decodeIfPresent([String].self, forKey: .failures) ?? []
        refused = try container.decodeIfPresent([String].self, forKey: .refused) ?? []
        plannedCount = try container.decodeIfPresent(Int.self, forKey: .plannedCount) ?? 0
        estimatedBytes = try container.decodeIfPresent(Int64.self, forKey: .estimatedBytes) ?? 0
    }
}
