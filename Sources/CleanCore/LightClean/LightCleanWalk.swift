/// The folder walk of PLAN §4.2 light clean: to depth 4 below the worktree root (`a/b/c/node_modules` is
/// depth 4), never into `.git`, into a folder whose name matched, into a symlink, or into another checkout
/// (a folder with its own `.git`: its folders belong to that checkout, and a linked worktree nested in a
/// main checkout gets its own light clean).
struct LightCleanWalk: Sendable {
    static let maxDepth = 4

    /// A folder (or symlink) whose name is in `RegenerableNames.folders`.
    struct Match: Sendable, Hashable {
        var relativePath: String
        var name: String
        var isSymlink: Bool
    }

    struct Result: Sendable, Hashable {
        /// Sorted by relative path.
        var matches: [Match]
        /// Folders that could not be read; nothing below them was looked at.
        var unreadable: [String]
    }

    func walk(_ root: String) -> Result {
        var result = Result(matches: [], unreadable: [])
        var pending: [(relative: String, depth: Int)] = [("", 0)]
        while let (relative, depth) = pending.popLast() {
            let folder = relative.isEmpty ? root : root + "/" + relative
            guard let entries = DirectoryEntries.read(folder) else {
                result.unreadable.append(relative.isEmpty ? "." : relative)
                continue
            }
            if !relative.isEmpty, entries.contains(where: { $0.name == ".git" }) { continue }
            for entry in entries where entry.name != ".git" {
                let child = relative.isEmpty ? entry.name : relative + "/" + entry.name
                if RegenerableNames.isRegenerableFolder(entry.name), entry.kind != .other {
                    result.matches.append(Match(relativePath: child, name: entry.name, isSymlink: entry.kind == .symlink))
                } else if entry.kind == .directory, depth + 1 < Self.maxDepth {
                    pending.append((child, depth + 1))
                }
            }
        }
        result.matches.sort { $0.relativePath < $1.relativePath }
        result.unreadable.sort()
        return result
    }
}
