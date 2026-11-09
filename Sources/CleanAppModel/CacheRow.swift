import CleanCore
import Foundation

/// One row of the Tool caches screen: a catalog entry the scan found, with the texts its columns show. Only a
/// ready row can be selected.
public struct CacheRow: Identifiable, Hashable, Sendable {
    /// How the status is drawn.
    public enum Tone: Sendable, Hashable {
        case ready
        /// An owner runs: it can be cleaned once that program quits.
        case waiting
        case refused
        case empty
        case displayOnly
    }

    public let finding: ToolCacheFinding
    let home: URL

    public init(finding: ToolCacheFinding, home: URL) {
        self.finding = finding
        self.home = home
    }

    public var id: String { finding.id }
    public var name: String { finding.entry.name }
    public var bytes: Int64? { finding.bytes }
    public var sizeText: String { DisplayText.bytes(bytes) }
    public var isSelectable: Bool { finding.isReady }
    public var isDisplayOnly: Bool { !finding.entry.isCleanable }
    public var note: String { finding.note }

    /// "~/Library/Caches/pip", "~/.npm: _cacache, _npx", or the paths joined when they share no folder.
    public var folderText: String {
        let paths = finding.paths.map { TildePath.abbreviate($0, home: home) }
        guard paths.count > 1 else { return paths.first ?? "–" }
        let parents = Set(paths.map { ($0 as NSString).deletingLastPathComponent })
        guard parents.count == 1, let parent = parents.first else { return paths.joined(separator: ", ") }
        return parent + ": " + paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
    }

    /// Every path in full, one per line (the folder cell's tooltip).
    public var folderHelp: String { finding.paths.joined(separator: "\n") }

    public var tone: Tone {
        switch finding.verdict {
        case .ready: .ready
        case .empty: .empty
        case .displayOnly: .displayOnly
        case .refused(let reason):
            !finding.runningOwners.isEmpty && reason == ToolOwner.quitSentence(finding.runningOwners) ? .waiting : .refused
        }
    }

    /// "Ready", "Quit npm to clean this", "Empty", the refusal, or why the row is shown only.
    public var statusText: String {
        switch finding.verdict {
        case .ready: "Ready"
        case .empty: "Empty"
        case .refused(let reason), .displayOnly(let reason): Self.sentence(reason)
        }
    }

    /// "Keeps 2026.10.19-6bbf2c4 (the version in use and the newest)"; nil when nothing is kept.
    public var keptText: String? {
        guard !finding.kept.isEmpty else { return nil }
        return "Keeps " + finding.kept.map { "\($0.name) (\($0.reason))" }.joined(separator: ", ")
    }

    /// What cleaning leaves alone, as the confirmation lists it: "the rest of ~/.npm", "~/.pub-cache/bin", the
    /// versions Cursor keeps. A long path is shown from the folder it shares with the target ("state.vscdb").
    public var keeps: [String] {
        let targets = finding.entry.targets
        let never = finding.entry.never.map { path -> String in
            let shown = "~/" + path
            if targets.contains(where: { $0.hasPrefix(path + "/") }) { return "the rest of \(shown)" }
            return shown.count <= 40 ? shown : Self.belowSharedFolder(path, targets.first ?? path)
        }
        return never + finding.kept.map { "version \($0.name) (\($0.reason))" }
    }

    /// `path` from below the folder it shares with `other`: `…/globalStorage/state.vscdb` next to
    /// `…/globalStorage/state.vscdb.backup` is `state.vscdb`.
    static func belowSharedFolder(_ path: String, _ other: String) -> String {
        let parts = path.split(separator: "/")
        let otherParts = other.split(separator: "/")
        var shared = 0
        while shared < parts.count - 1, shared < otherParts.count, parts[shared] == otherParts[shared] { shared += 1 }
        return parts[shared...].joined(separator: "/")
    }

    /// The first letter in upper case.
    static func sentence(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
