import Foundation

/// A DerivedData folder whose project is gone: what `DerivedDataCleaner.delete` takes. Only
/// `DerivedDataScanner` makes these (the initializer is internal), and only for orphaned entries, so a
/// live, internal or plist-less folder can't be passed in.
public struct OrphanedDerivedData: Sendable, Hashable, Encodable {
    /// The DerivedData root it was found in.
    public let root: String
    /// The folder's name inside the root (`App-abcdef...`).
    public let name: String
    /// The workspace `info.plist` named, which did not exist at scan time.
    public let workspacePath: String
    /// `du -skx` estimate.
    public let bytes: Int64?

    public var folder: String { root + "/" + name }
    public var url: URL { URL(fileURLWithPath: folder, isDirectory: true) }
}
