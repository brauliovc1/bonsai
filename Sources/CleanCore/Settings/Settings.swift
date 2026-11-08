import Foundation

/// The settings shared by the app and the CLI (`<settingsDir>/settings.json`, PLAN §3).
///
/// Every key is optional when decoding: a file with only some keys gets defaults for the rest, and keys
/// this version does not know are ignored.
public struct Settings: Sendable, Codable, Equatable {
    /// The days `idleThresholdDays` may be (PLAN §3). Below it, a worktree touched last week would be
    /// auto-ready.
    public static let idleThresholdRange = 7...365

    /// Folders to scan; empty = the default root (`~/Documents/GitHub`). `~` is expanded. Only folders
    /// `ScanRootRule` accepts are used; the others are reported (`refusedScanRoots`) and skipped.
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
    /// When the app last showed the low-disk-space notification (at most one a day).
    public var lowSpaceNotifiedAt: Date?

    public init(
        scanRoots: [String] = [],
        idleThresholdDays: Int = 30,
        lowSpaceWarningGB: Int = 10,
        autoEnabled: Bool = false,
        autoEnabledAt: Date? = nil,
        reportOnlyDays: Int = 7,
        includeClaudeInAuto: Bool = false,
        lastAutoRun: AutoRunSummary? = nil,
        lowSpaceNotifiedAt: Date? = nil
    ) {
        self.scanRoots = scanRoots
        self.idleThresholdDays = idleThresholdDays
        self.lowSpaceWarningGB = lowSpaceWarningGB
        self.autoEnabled = autoEnabled
        self.autoEnabledAt = autoEnabledAt
        self.reportOnlyDays = reportOnlyDays
        self.includeClaudeInAuto = includeClaudeInAuto
        self.lastAutoRun = lastAutoRun
        self.lowSpaceNotifiedAt = lowSpaceNotifiedAt
    }

    private enum CodingKeys: String, CodingKey {
        case scanRoots, idleThresholdDays, lowSpaceWarningGB, autoEnabled, autoEnabledAt, reportOnlyDays
        case includeClaudeInAuto, lastAutoRun, lowSpaceNotifiedAt
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
        lowSpaceNotifiedAt = try container.decodeIfPresent(Date.self, forKey: .lowSpaceNotifiedAt)
    }

    /// What makes these settings unusable; empty when they are fine. A threshold below 7 days would make
    /// a worktree used last week auto-ready.
    public var problems: [String] {
        var problems: [String] = []
        let range = Self.idleThresholdRange
        if !range.contains(idleThresholdDays) {
            problems.append("idleThresholdDays must be \(range.lowerBound) to \(range.upperBound) (is \(idleThresholdDays))")
        }
        if reportOnlyDays < 0 { problems.append("reportOnlyDays must not be negative (is \(reportOnlyDays))") }
        return problems
    }

    /// The threshold the rules apply: never below the lowest allowed, whatever was set in code.
    public var effectiveIdleThresholdDays: Int { max(Self.idleThresholdRange.lowerBound, idleThresholdDays) }

    /// `scanRoots` as canonical folders (`~` expanded against `home`, symlinks resolved), without the ones
    /// `ScanRootRule` refuses.
    public func scanRootURLs(home: URL) -> [URL] {
        let rule = ScanRootRule(home: home)
        return writtenScanRoots(home: home).compactMap { rule.canonical($0) }.uniqued()
    }

    /// The saved roots that are skipped, with why.
    public func refusedScanRoots(home: URL) -> [ScanRootRule.Refusal] {
        let rule = ScanRootRule(home: home)
        return writtenScanRoots(home: home).compactMap { root in
            if case .failure(let refusal) = rule.accept(root) { refusal } else { nil }
        }
    }

    private func writtenScanRoots(home: URL) -> [URL] {
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
