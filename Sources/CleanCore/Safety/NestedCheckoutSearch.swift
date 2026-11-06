import Foundation

/// Finds other git checkouts inside a worktree (PLAN §4.1 "Nested checkouts"): every folder below it with a
/// `.git` entry, including inside §4.2 folders (`pip install -e git+...` clones into `.venv/src`), and every
/// bare repo (a folder with a `HEAD` file and `objects` and `refs` folders, like SwiftPM's and Xcode's
/// `repositories/` mirrors).
///
/// `git worktree remove` deletes ignored folders and everything in them, so a clone or worktree in one would
/// go too. The walk uses `readdir` (no `stat` per file), never follows symlinks, and does not descend into a
/// checkout it found. Hitting the entry cap or an unreadable folder makes the result incomplete.
public struct NestedCheckoutSearch: Sendable {
    public static let defaultLimit = 500_000

    public var limit: Int

    public init(limit: Int = NestedCheckoutSearch.defaultLimit) {
        self.limit = limit
    }

    public struct Result: Sendable, Equatable {
        /// Folders with their own `.git`, and bare repos, relative to the worktree, sorted.
        public var checkouts: [String]
        /// The checkouts whose `.git` is not a folder (a linked worktree or submodule of some repo): never
        /// a plain clone.
        public var gitFiles: [String]
        /// The checkouts that are bare repos (no `.git` entry).
        public var bareRepos: [String] = []
        /// Why the walk could not look everywhere (cap hit, unreadable folder); nil when it finished.
        public var incomplete: String?
        public var entries: Int
    }

    public func search(_ worktree: URL) -> Result {
        let root = worktree.path
        var result = Result(checkouts: [], gitFiles: [], incomplete: nil, entries: 0)
        var pending: [String] = [""]

        while let relative = pending.popLast() {
            let folder = relative.isEmpty ? root : root + "/" + relative
            guard let directory = opendir(folder) else {
                if result.incomplete == nil { result.incomplete = "cannot read \(relative.isEmpty ? "." : relative)" }
                continue
            }
            defer { closedir(directory) }

            var children: [(name: String, isDirectory: Bool)] = []
            var hasGit = false
            var gitIsDirectory = false
            while let entry = readdir(directory) {
                let name = Self.name(of: entry)
                if name == "." || name == ".." { continue }
                result.entries += 1
                if result.entries > limit {
                    result.incomplete = "stopped after \(limit) entries"
                    result.checkouts.sort()
                    result.gitFiles.sort()
                    result.bareRepos.sort()
                    return result
                }
                if name == ".git" {
                    hasGit = true
                    gitIsDirectory = Self.isDirectory(entry, path: folder + "/.git")
                    continue
                }
                children.append((name, Self.isDirectory(entry, path: folder + "/" + name)))
            }
            if hasGit, !relative.isEmpty {
                result.checkouts.append(relative)
                if !gitIsDirectory { result.gitFiles.append(relative) }
                continue
            }
            if !relative.isEmpty, Self.isBareRepo(children) {
                result.checkouts.append(relative)
                result.bareRepos.append(relative)
                continue
            }
            for child in children where child.isDirectory {
                pending.append(relative.isEmpty ? child.name : relative + "/" + child.name)
            }
        }
        result.checkouts.sort()
        result.gitFiles.sort()
        result.bareRepos.sort()
        return result
    }

    /// git's own test for a repo directory: a `HEAD` file next to `objects` and `refs` folders.
    static func isBareRepo(_ entries: [(name: String, isDirectory: Bool)]) -> Bool {
        entries.contains { $0.name == "HEAD" && !$0.isDirectory }
            && entries.contains { $0.name == "objects" && $0.isDirectory }
            && entries.contains { $0.name == "refs" && $0.isDirectory }
    }

    /// `folder` itself is a bare repo.
    public static func isBareRepo(_ folder: URL) -> Bool {
        guard let entries = DirectoryEntries.read(folder.path) else { return false }
        return isBareRepo(entries.map { ($0.name, $0.kind == .directory) })
    }

    private static func name(of entry: UnsafeMutablePointer<dirent>) -> String {
        withUnsafeBytes(of: entry.pointee.d_name) { buffer in
            let length = Int(entry.pointee.d_namlen)
            return String(decoding: buffer.prefix(length), as: UTF8.self)
        }
    }

    /// A real folder (not a symlink). `DT_UNKNOWN` falls back to `lstat`.
    private static func isDirectory(_ entry: UnsafeMutablePointer<dirent>, path: String) -> Bool {
        switch Int32(entry.pointee.d_type) {
        case DT_DIR: return true
        case DT_UNKNOWN:
            var info = stat()
            return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
        default: return false
        }
    }
}
