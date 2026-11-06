import Foundation

/// Whether a folder may serve as the DerivedData root (PLAN §4.4): never `/`, the home folder, a folder
/// that contains the home folder, or something that is not a folder. A root that does not exist is fine
/// (nothing is listed). Symlinks are resolved first, so `~/Library/..` is the home folder.
enum DerivedDataRootCheck {
    /// Why `root` is refused, or nil.
    static func refusal(root: URL, home: URL) -> String? {
        let resolved = CanonicalPath.resolve(root)
        let homePath = CanonicalPath.resolve(home)
        if resolved == "/" { return "\(root.path) is the root of the disk, not a DerivedData folder" }
        if resolved == homePath { return "\(root.path) is the home folder, not a DerivedData folder" }
        if homePath.hasPrefix(resolved + "/") { return "\(root.path) contains the home folder, so it is not a DerivedData folder" }
        if let kind = FileIdentity.of(resolved)?.kind, kind != .directory {
            return "\(root.path) is not a folder"
        }
        return nil
    }
}
