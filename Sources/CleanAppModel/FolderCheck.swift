import Foundation

/// Checks on folders before the app hands them to Finder or Terminal.
public enum FolderCheck {
    /// True only for an existing directory that is not a symlink. A file is not enough: Terminal runs a
    /// `.command` or executable file it is asked to open.
    public static func isRealDirectory(_ url: URL) -> Bool {
        // attributesOfItem doesn't follow a final symlink, so a link to a folder reports .typeSymbolicLink.
        let type = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType
        return type == .typeDirectory
    }
}
