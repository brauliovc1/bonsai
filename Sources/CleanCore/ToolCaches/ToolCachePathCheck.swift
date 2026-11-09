import Foundation

/// The PLAN §4.6 path rules for one catalog path: every component from the home folder down is looked at with
/// `lstat` (a symlink anywhere refuses), every one is owned by the current user, and the last one is the kind
/// expected. The home folder itself is not checked (a temp home sits under `/var`, itself a link).
enum ToolCachePathCheck {
    enum Expect: Sendable, Hashable {
        case directory
        case file
        /// A symlink (Cursor's `.local/bin/cursor-agent`); only the components above it must be folders.
        case link
        /// A display-only path: a file or a folder.
        case any
    }

    enum Outcome: Sendable, Hashable {
        /// A component doesn't exist.
        case missing
        /// The path passed; the identity of its last component.
        case passed(FileIdentity)
        case refused(String)
    }

    static func check(_ relative: String, home: URL, expect: Expect, uid: uid_t = getuid()) -> Outcome {
        let parts = relative.split(separator: "/", omittingEmptySubsequences: true)
        guard !parts.isEmpty, !parts.contains(where: { $0 == "." || $0 == ".." }) else {
            return .refused("\(relative) is not a path inside the home folder")
        }
        var path = home.standardized.path
        for (position, part) in parts.enumerated() {
            path += "/" + part
            let shown = TildePath.abbreviate(path, home: home)
            var info = stat()
            guard lstat(path, &info) == 0 else {
                let code = errno
                if code == ENOENT || code == ENOTDIR { return .missing }
                return .refused("\(shown) can't be looked at: \(String(cString: strerror(code)))")
            }
            let isLast = position == parts.count - 1
            let type = info.st_mode & S_IFMT
            if type == S_IFLNK, !(isLast && expect == .link) {
                return .refused("\(shown) is a symbolic link")
            }
            guard info.st_uid == uid else {
                return .refused("\(shown) belongs to \(userName(info.st_uid)), not to you")
            }
            if !isLast {
                guard type == S_IFDIR else { return .refused("\(shown) is not a folder") }
                continue
            }
            switch expect {
            case .directory where type != S_IFDIR: return .refused("\(shown) is not a folder")
            case .file where type != S_IFREG: return .refused("\(shown) is not a plain file")
            case .link where type != S_IFLNK: return .refused("\(shown) is not a symbolic link")
            case .any where type != S_IFDIR && type != S_IFREG: return .refused("\(shown) is not a file or a folder")
            default: break
            }
            let kind: DirectoryEntries.Kind = type == S_IFDIR ? .directory : type == S_IFLNK ? .symlink : .other
            return .passed(FileIdentity(kind: kind, device: info.st_dev, inode: info.st_ino))
        }
        return .missing
    }

    /// The user's short name, or "user <uid>".
    static func userName(_ uid: uid_t) -> String {
        guard let entry = getpwuid(uid), let name = entry.pointee.pw_name else { return "user \(uid)" }
        return String(cString: name)
    }
}
