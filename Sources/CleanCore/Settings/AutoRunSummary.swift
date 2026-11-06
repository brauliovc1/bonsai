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
    /// One line per worktree that could not be removed.
    public var failures: [String]

    public init(
        date: Date,
        reportOnly: Bool,
        removedCount: Int = 0,
        freedBytes: Int64 = 0,
        notifiedCount: Int = 0,
        failures: [String] = []
    ) {
        self.date = date
        self.reportOnly = reportOnly
        self.removedCount = removedCount
        self.freedBytes = freedBytes
        self.notifiedCount = notifiedCount
        self.failures = failures
    }

    private enum CodingKeys: String, CodingKey {
        case date, reportOnly, removedCount, freedBytes, notifiedCount, failures
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? .distantPast
        reportOnly = try container.decodeIfPresent(Bool.self, forKey: .reportOnly) ?? true
        removedCount = try container.decodeIfPresent(Int.self, forKey: .removedCount) ?? 0
        freedBytes = try container.decodeIfPresent(Int64.self, forKey: .freedBytes) ?? 0
        notifiedCount = try container.decodeIfPresent(Int.self, forKey: .notifiedCount) ?? 0
        failures = try container.decodeIfPresent([String].self, forKey: .failures) ?? []
    }
}
