import Foundation

/// Everything `ToolCacheScanner` found: one finding per catalog entry with at least one path present, in
/// catalog order.
public struct ToolCacheReport: Sendable, Hashable, Encodable {
    public var findings: [ToolCacheFinding]
    /// The Cursor app was running at scan time (ps, and NSWorkspace in the app).
    public var cursorRunning: Bool
    /// Why the process list couldn't be read (every entry is refused then).
    public var processListFailure: String?
    public var warnings: [String]

    public init(findings: [ToolCacheFinding], cursorRunning: Bool, processListFailure: String? = nil, warnings: [String] = []) {
        self.findings = findings
        self.cursorRunning = cursorRunning
        self.processListFailure = processListFailure
        self.warnings = warnings
    }

    public var ready: [ToolCacheFinding] { findings.filter(\.isReady) }
    public var readyBytes: Int64 { ready.compactMap(\.bytes).reduce(0, +) }

    public func findings(in section: ToolCacheEntry.Section) -> [ToolCacheFinding] {
        findings.filter { $0.entry.section == section }
    }

    public func finding(id: String) -> ToolCacheFinding? {
        findings.first { $0.id == id }
    }

    private enum CodingKeys: String, CodingKey {
        case entries, cursorRunning, processListFailure, warnings, readyCount, readyBytes
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(findings, forKey: .entries)
        try container.encode(cursorRunning, forKey: .cursorRunning)
        try container.encode(processListFailure, forKey: .processListFailure)
        try container.encode(warnings, forKey: .warnings)
        try container.encode(ready.count, forKey: .readyCount)
        try container.encode(readyBytes, forKey: .readyBytes)
    }
}
