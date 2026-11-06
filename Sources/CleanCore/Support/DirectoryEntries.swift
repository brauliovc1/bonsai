import Foundation

/// The entries of one folder, read with `readdir`: names keep the bytes they are stored with (no
/// normalization), and the type comes from `d_type`, so symlinks are never followed.
enum DirectoryEntries {
    enum Kind: Sendable, Hashable {
        case directory
        case symlink
        /// A file, a socket, anything else.
        case other
    }

    struct Entry: Sendable, Hashable {
        var name: String
        var kind: Kind
    }

    /// Every entry but `.` and `..`; nil when the folder can't be opened.
    static func read(_ folder: String) -> [Entry]? {
        guard let directory = opendir(folder) else { return nil }
        defer { closedir(directory) }
        var entries: [Entry] = []
        while let entry = readdir(directory) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { buffer in
                String(decoding: buffer.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self)
            }
            if name == "." || name == ".." { continue }
            entries.append(Entry(name: name, kind: kind(entry, path: folder + "/" + name)))
        }
        return entries
    }

    /// What is at `path` without following a symlink there; nil when nothing is (or it can't be looked at).
    static func kind(ofItemAt path: String) -> Kind? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return kind(mode: info.st_mode)
    }

    private static func kind(_ entry: UnsafeMutablePointer<dirent>, path: String) -> Kind {
        switch Int32(entry.pointee.d_type) {
        case DT_DIR: return .directory
        case DT_LNK: return .symlink
        case DT_UNKNOWN: return kind(ofItemAt: path) ?? .other
        default: return .other
        }
    }

    private static func kind(mode: mode_t) -> Kind {
        switch mode & S_IFMT {
        case S_IFDIR: .directory
        case S_IFLNK: .symlink
        default: .other
        }
    }
}
