import Foundation

/// Whether anything is at a path, telling "not there" apart from "could not look". Only `ENOENT` and
/// `ENOTDIR` mean missing: a folder the process may not search (permissions, macOS privacy protection)
/// gives `EACCES` or `EPERM`, which says nothing about what is inside. Symlinks are not followed, so a
/// dangling link counts as present.
enum PathPresence: Sendable, Hashable {
    case present
    case missing
    /// lstat failed for another reason (the text says why).
    case unknown(String)

    static func of(_ path: String) -> PathPresence {
        var info = stat()
        if lstat(path, &info) == 0 { return .present }
        let code = errno
        if code == ENOENT || code == ENOTDIR { return .missing }
        return .unknown(String(cString: strerror(code)))
    }
}
