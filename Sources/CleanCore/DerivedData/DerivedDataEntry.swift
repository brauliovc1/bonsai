/// One folder in the DerivedData root.
public struct DerivedDataEntry: Sendable, Hashable, Encodable {
    /// Absolute path.
    public let folder: String
    public let name: String
    /// `WorkspacePath` from `info.plist`, when it has one.
    public let workspacePath: String?
    public let state: DerivedDataState
    /// Why the state is `unreadable`; nil otherwise.
    public let detail: String?
    /// `du -skx` estimate; nil when it could not be measured.
    public let bytes: Int64?
    /// Set only for an orphaned entry: what `DerivedDataCleaner.delete` takes.
    public let orphan: OrphanedDerivedData?
}
