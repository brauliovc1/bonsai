import Foundation

/// The contents covered by an Empty Trash confirmation. Symlinks are recorded, never followed.
public enum TrashFingerprint: Sendable, Hashable {
    case missing
    case unreadable
    case contents([String: FileStamp])

    public static func capture(home: URL) async -> Self {
        let root = home.resolvingSymlinksInPath().appending(path: ".Trash").path
        guard let kind = DirectoryEntries.kind(ofItemAt: root) else { return errno == ENOENT ? .missing : .unreadable }
        guard kind == .directory, let rootStamp = FileStamp.of(root) else { return .unreadable }
        var stamps = ["": rootStamp]
        var pending = [(path: root, relative: "")]
        while let folder = pending.popLast() {
            guard let children = DirectoryEntries.read(folder.path) else { return .unreadable }
            for child in children {
                let path = folder.path + "/" + child.name
                let relative = folder.relative.isEmpty ? child.name : folder.relative + "/" + child.name
                guard let stamp = FileStamp.of(path), let currentKind = DirectoryEntries.kind(ofItemAt: path) else { return .unreadable }
                stamps[relative] = stamp
                if currentKind == .directory { pending.append((path, relative)) }
            }
        }
        guard FileStamp.of(root) == rootStamp else { return .unreadable }
        return .contents(stamps)
    }
}
