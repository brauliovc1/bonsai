import Foundation

/// Finds the newest file modification in a worktree (PLAN §4.3, signal 3).
///
/// Skips `.git`, the regenerable folders of §4.2, symlinked folders, and nested repos or worktrees
/// (folders with their own `.git`, such as `<repo>/.claude/worktrees/*` inside a main checkout). Only
/// files count: a folder's mtime also moves when `node_modules` or `dist` appears in it.
public struct FileActivityWalk: Sendable {
    public static let defaultMaxEntries = 20_000

    public var maxEntries: Int

    public init(maxEntries: Int = FileActivityWalk.defaultMaxEntries) {
        self.maxEntries = maxEntries
    }

    public struct Result: Sendable, Equatable {
        public var newest: Date?
        /// More than `maxEntries` entries: the walk stopped early, so `newest` may be wrong.
        public var capHit: Bool
        public var entries: Int
        public var errors: [String]
    }

    private static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey,
    ]

    public func walk(_ root: URL) -> Result {
        var result = Result(newest: nil, capHit: false, entries: 0, errors: [])
        var pending: [URL] = [root]
        let fileManager = FileManager.default

        while let folder = pending.popLast() {
            let children: [URL]
            do {
                children = try fileManager.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: Array(Self.keys),
                    options: []
                )
            } catch {
                result.errors.append("cannot read \(folder.path)")
                continue
            }
            for child in children {
                let name = child.lastPathComponent
                if name == ".git" { continue }
                result.entries += 1
                if result.entries > maxEntries {
                    result.capHit = true
                    return result
                }
                guard let values = try? child.resourceValues(forKeys: Self.keys) else {
                    result.errors.append("cannot read \(child.path)")
                    continue
                }
                if values.isDirectory == true, values.isSymbolicLink != true {
                    if RegenerableNames.isRegenerableFolder(name) { continue }
                    if fileManager.fileExists(atPath: child.appending(path: ".git").path) { continue }
                    pending.append(child)
                    continue
                }
                if values.isDirectory == true { continue }
                if let date = values.contentModificationDate, result.newest.map({ date > $0 }) ?? true {
                    result.newest = date
                }
            }
        }
        return result
    }
}
