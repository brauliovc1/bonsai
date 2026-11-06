import Foundation

/// The settings shared by the app and the CLI (`<settingsDir>/settings.json`, PLAN §3).
///
/// Every key is optional when decoding: a file with only some keys gets defaults for the rest, and keys
/// this version does not know are ignored.
public struct Settings: Sendable, Codable, Equatable {
    /// Folders to scan; empty = the default root (`~/Documents/GitHub`). `~` is expanded.
    public var scanRoots: [String]
    /// A worktree counts as idle for auto mode after this many days without activity (PLAN §4.3).
    public var idleThresholdDays: Int
    public var lowSpaceWarningGB: Int
    public var autoEnabled: Bool
    /// When auto mode was turned on; the report-only window starts here.
    public var autoEnabledAt: Date?
    /// Auto mode only reports, and removes nothing, for this many days after it is turned on.
    public var reportOnlyDays: Int
    /// Auto mode skips Claude-app worktrees unless this is on.
    public var includeClaudeInAuto: Bool
    public var lastAutoRun: AutoRunSummary?

    public init(
        scanRoots: [String] = [],
        idleThresholdDays: Int = 30,
        lowSpaceWarningGB: Int = 10,
        autoEnabled: Bool = false,
        autoEnabledAt: Date? = nil,
        reportOnlyDays: Int = 7,
        includeClaudeInAuto: Bool = false,
        lastAutoRun: AutoRunSummary? = nil
    ) {
        self.scanRoots = scanRoots
        self.idleThresholdDays = idleThresholdDays
        self.lowSpaceWarningGB = lowSpaceWarningGB
        self.autoEnabled = autoEnabled
        self.autoEnabledAt = autoEnabledAt
        self.reportOnlyDays = reportOnlyDays
        self.includeClaudeInAuto = includeClaudeInAuto
        self.lastAutoRun = lastAutoRun
    }

    private enum CodingKeys: String, CodingKey {
        case scanRoots, idleThresholdDays, lowSpaceWarningGB, autoEnabled, autoEnabledAt, reportOnlyDays
        case includeClaudeInAuto, lastAutoRun
    }

    public init(from decoder: Decoder) throws {
        let defaults = Settings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scanRoots = try container.decodeIfPresent([String].self, forKey: .scanRoots) ?? defaults.scanRoots
        idleThresholdDays = try container.decodeIfPresent(Int.self, forKey: .idleThresholdDays)
            ?? defaults.idleThresholdDays
        lowSpaceWarningGB = try container.decodeIfPresent(Int.self, forKey: .lowSpaceWarningGB)
            ?? defaults.lowSpaceWarningGB
        autoEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoEnabled) ?? defaults.autoEnabled
        autoEnabledAt = try container.decodeIfPresent(Date.self, forKey: .autoEnabledAt)
        reportOnlyDays = try container.decodeIfPresent(Int.self, forKey: .reportOnlyDays) ?? defaults.reportOnlyDays
        includeClaudeInAuto = try container.decodeIfPresent(Bool.self, forKey: .includeClaudeInAuto)
            ?? defaults.includeClaudeInAuto
        lastAutoRun = try container.decodeIfPresent(AutoRunSummary.self, forKey: .lastAutoRun)
    }

    /// `scanRoots` as absolute URLs, with `~` expanded against `home`.
    public func scanRootURLs(home: URL) -> [URL] {
        scanRoots.filter { !$0.isEmpty }.map { CleanEnvironment.expand($0, home: home) }
    }

    /// The end of the report-only window, or nil when auto mode has no start date.
    public var reportOnlyEndsAt: Date? {
        autoEnabledAt.map { $0.addingTimeInterval(TimeInterval(reportOnlyDays) * 86_400) }
    }

    /// True while auto mode should only report. Without a start date it is report-only too: when in
    /// doubt, nothing is removed.
    public func isReportOnly(now: Date) -> Bool {
        guard let end = reportOnlyEndsAt else { return true }
        return now < end
    }
}
