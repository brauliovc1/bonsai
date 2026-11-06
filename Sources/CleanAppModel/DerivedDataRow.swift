import CleanCore
import Foundation

/// One row of the DerivedData table: a folder of the root with its state, size, and the one line that says
/// why it can't be deleted (everything but an orphan is read-only).
public struct DerivedDataRow: Identifiable, Hashable, Sendable {
    /// How the state badge is drawn.
    public enum Tone: Sendable, Hashable {
        case orphaned, live, internalOrCache, warning
    }

    public let entry: DerivedDataEntry

    public init(entry: DerivedDataEntry) {
        self.entry = entry
    }

    /// The folder's absolute path.
    public var id: String { entry.folder }
    public var name: String { entry.name }
    public var state: DerivedDataState { entry.state }
    public var stateText: String { entry.state.label }
    public var projectPath: String { entry.workspacePath ?? "–" }
    public var bytes: Int64? { entry.bytes }
    public var sizeText: String { DisplayText.bytes(bytes) }
    public var sizeSortKey: Int64 { bytes ?? -1 }

    /// Only an orphan can be selected, and only one the scanner made (`entry.orphan`).
    public var isSelectable: Bool { entry.orphan != nil }

    public var tone: Tone {
        switch entry.state {
        case .orphaned: .orphaned
        case .live: .live
        case .xcodeInternal, .noInfoPlist: .internalOrCache
        case .volumeMissing, .unreadable: .warning
        }
    }

    /// One line: why this folder stays (or, for an orphan, why it can go).
    public var reason: String {
        switch entry.state {
        case .orphaned:
            "Its project is gone: \(entry.workspacePath ?? "unknown path")."
        case .live:
            "Its project still exists, so Xcode reuses this folder. Read-only."
        case .xcodeInternal:
            "A temporary workspace of Xcode's own. Read-only."
        case .volumeMissing:
            "On a drive that isn't connected: its project may be there when the drive is. Read-only."
        case .noInfoPlist:
            "Xcode's shared cache (no info.plist), never touched. Read-only."
        case .unreadable:
            "Couldn't tell what it belongs to" + (entry.detail.map { " (\($0))" } ?? "") + ". Read-only."
        }
    }
}
