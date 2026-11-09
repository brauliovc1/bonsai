import Foundation

/// One catalog entry as `ToolCacheScanner` found it: which of its paths exist, how big what would go is, and
/// whether it can be cleaned now. Only the scanner makes findings; `ToolCacheCleaner` takes them as what the
/// person confirmed and checks every one again.
public struct ToolCacheFinding: Sendable, Hashable, Identifiable {
    public enum Verdict: Sendable, Hashable {
        case ready
        /// Its targets exist but hold nothing to delete.
        case empty
        /// It may not be cleaned now: an owner runs ("Quit npm to clean this"), a path rule, a Cursor rule.
        case refused(String)
        /// Never cleaned; shown with its size.
        case displayOnly(String)

        public var label: String {
            switch self {
            case .ready: "ready"
            case .empty: "empty"
            case .refused: "refused"
            case .displayOnly: "display-only"
            }
        }

        public var reason: String? {
            switch self {
            case .ready, .empty: nil
            case .refused(let why), .displayOnly(let why): why
            }
        }
    }

    public let entry: ToolCacheEntry
    /// Absolute paths of the entry's paths that exist.
    public let paths: [String]
    /// What would go: the target folders (their contents go), the version folders, or the backup file.
    public let removals: [String]
    /// Cursor agent versions that stay, with why.
    public let kept: [CursorAgentVersions.Kept]
    /// Estimated bytes of what would go (`du`); for an entry that can't be cleaned now, of what is there.
    /// nil when it wasn't measured.
    public let bytes: Int64?
    public let verdict: Verdict
    /// Owners running at scan time.
    public let runningOwners: [String]
    /// The entry's note, with the backup's date for Cursor's backup.
    public let note: String
    /// What lstat saw at each present path; the cleaner refuses a backup that was replaced since.
    let identities: [String: FileIdentity]

    public var id: String { entry.id }
    public var isReady: Bool { verdict == .ready }

    init(inspection: ToolCacheInspection, bytes: Int64?) {
        entry = inspection.entry
        paths = inspection.present.map(\.path)
        removals = inspection.removals
        kept = inspection.kept
        self.bytes = bytes
        runningOwners = inspection.runningOwners
        identities = Dictionary(inspection.present.compactMap { present in present.identity.map { (present.path, $0) } }) { first, _ in first }
        if case .cursorStateBackup = inspection.entry.deletion {
            note = CursorStateBackup.note(date: inspection.backupDate)
        } else {
            note = inspection.entry.note
        }
        if let reason = inspection.entry.displayOnlyReason {
            verdict = .displayOnly(reason)
        } else if let refusal = inspection.refusal {
            verdict = .refused(refusal)
        } else if inspection.isEmpty {
            verdict = .empty
        } else {
            verdict = .ready
        }
    }
}

extension ToolCacheFinding: Encodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, section, paths, removals, kept, never, bytes, verdict, reason, runningOwners, note
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entry.id, forKey: .id)
        try container.encode(entry.name, forKey: .name)
        try container.encode(entry.section, forKey: .section)
        try container.encode(paths, forKey: .paths)
        try container.encode(removals, forKey: .removals)
        try container.encode(kept, forKey: .kept)
        try container.encode(entry.never, forKey: .never)
        try container.encode(bytes, forKey: .bytes)
        try container.encode(verdict.label, forKey: .verdict)
        try container.encode(verdict.reason, forKey: .reason)
        try container.encode(runningOwners, forKey: .runningOwners)
        try container.encode(note, forKey: .note)
    }
}
