/// What one DerivedData folder is (PLAN §4.4). Only `orphaned` folders can be deleted.
public enum DerivedDataState: String, Sendable, Hashable, Codable, CaseIterable {
    /// `info.plist` names a workspace that no longer exists (and is not one of Xcode's temp workspaces).
    case orphaned
    /// The workspace exists: shown, never deleted in v1.
    case live
    /// The workspace is under `/var/folders` or `/private/var/folders` (Xcode's own temp workspaces).
    case xcodeInternal
    /// No `info.plist` (ModuleCache.noindex, SDKExplicitPrecompiledModules): never touched.
    case noInfoPlist
    /// `info.plist` can't be read or has no usable `WorkspacePath`, or the workspace path can't be checked.
    case unreadable

    public var label: String {
        switch self {
        case .orphaned: "orphaned"
        case .live: "live"
        case .xcodeInternal: "Xcode internal"
        case .noInfoPlist: "no info.plist"
        case .unreadable: "unreadable"
        }
    }
}
