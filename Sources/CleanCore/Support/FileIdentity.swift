import Foundation

/// What lstat says is at a path: its type and which file it is (device and inode), symlinks not followed.
/// Two readings with the same device and inode are the same file, whatever happened to the path between.
struct FileIdentity: Sendable, Hashable {
    var kind: DirectoryEntries.Kind
    var device: Int32
    var inode: UInt64

    /// nil when nothing is at `path` or it can't be looked at.
    static func of(_ path: String) -> FileIdentity? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        let kind: DirectoryEntries.Kind = switch info.st_mode & S_IFMT {
        case S_IFDIR: .directory
        case S_IFLNK: .symlink
        default: .other
        }
        return FileIdentity(kind: kind, device: info.st_dev, inode: info.st_ino)
    }
}
