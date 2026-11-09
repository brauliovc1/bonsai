import Foundation

/// One row of the tool-cache catalog (PLAN §4.6): a package manager's download cache or a piece of Cursor's
/// data. Paths are relative to the home folder and fixed: never read from a tool's config or the environment.
///
/// Only `ToolCacheCatalog` makes entries (the initializer is internal), and `ToolCacheCleaner` looks every
/// entry up in the catalog again by id, so nothing outside the table can be handed to it.
public struct ToolCacheEntry: Sendable, Hashable, Identifiable {
    public enum Section: String, Sendable, Hashable, Codable, CaseIterable {
        case packages
        case cursor

        public var title: String {
            switch self {
            case .packages: "Package caches"
            case .cursor: "Cursor"
            }
        }
    }

    /// What cleaning the entry deletes.
    public enum Deletion: Sendable, Hashable {
        /// The top-level children of every target folder, one by one; the folders themselves stay.
        case contents
        /// The folders in Cursor's agent `versions/` folder except the ones `CursorAgentVersions` keeps.
        case cursorAgentVersions
        /// Cursor's `state.vscdb.backup`, when `CursorStateBackup` allows it.
        case cursorStateBackup
        /// Nothing: shown with its size and this reason, never deleted.
        case none(reason: String)
    }

    public let id: String
    public let name: String
    public let section: Section
    public let deletion: Deletion
    /// Relative to the home folder: the folders (or the one file) the entry is about. For a cleanable entry
    /// these are its targets; for a display-only one, what is measured.
    public let paths: [String]
    /// Relative to the home folder: what cleaning leaves alone (the tests check every one survives, the
    /// confirmation lists them). A folder here keeps everything in it that no target covers.
    public let never: [String]
    /// Programs that must not be running while the entry is cleaned.
    public let owners: [ToolOwner]
    /// When it comes back ("npm downloads them again on the next install.").
    public let note: String

    init(
        id: String,
        name: String,
        section: Section,
        deletion: Deletion = .contents,
        paths: [String],
        never: [String] = [],
        owners: [ToolOwner],
        note: String
    ) {
        self.id = id
        self.name = name
        self.section = section
        self.deletion = deletion
        self.paths = paths
        self.never = never
        self.owners = owners
        self.note = note
    }

    public var isCleanable: Bool {
        if case .none = deletion { return false }
        return true
    }

    /// Why it is shown only; nil for a cleanable entry.
    public var displayOnlyReason: String? {
        if case .none(let reason) = deletion { return reason }
        return nil
    }

    /// The paths cleaning deletes from; empty for a display-only entry.
    public var targets: [String] { isCleanable ? paths : [] }

    /// What each path must be: the backup and `state.vscdb` are files, everything else a folder.
    var pathKind: ToolCachePathCheck.Expect {
        switch deletion {
        case .cursorStateBackup: .file
        case .none: .any
        case .contents, .cursorAgentVersions: .directory
        }
    }
}
