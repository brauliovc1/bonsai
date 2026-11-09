import Foundation

/// What lstat says about a file at one moment: which file it is, its size and when it was last changed.
/// Symlinks are not followed. Two stamps of a path differ when it was written, replaced or removed between
/// them (PLAN §4.8: an edit after the Remove anyway confirmation is a change).
public struct FileStamp: Sendable, Hashable {
    public var device: Int32
    public var inode: UInt64
    public var size: Int64
    public var modifiedSeconds: Int
    public var modifiedNanoseconds: Int

    /// nil when nothing is at `path` or it can't be looked at.
    public static func of(_ path: String) -> FileStamp? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return FileStamp(
            device: info.st_dev,
            inode: info.st_ino,
            size: Int64(info.st_size),
            modifiedSeconds: info.st_mtimespec.tv_sec,
            modifiedNanoseconds: info.st_mtimespec.tv_nsec
        )
    }
}
