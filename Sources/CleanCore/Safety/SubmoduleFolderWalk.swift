import Foundation

/// The files in a submodule's folder that has no `.git` of its own (an uninitialized submodule): `git status` and the
/// ignored listing don't look there, so `git worktree remove --force` would delete them unlisted (P12b review). Read
/// with `readdir`, symlinks not followed (a link is listed as itself), at most `limit` entries.
enum SubmoduleFolderWalk {
    static let defaultLimit = 10_000

    struct Result: Sendable, Hashable {
        /// Relative to the worktree, sorted.
        var files: [String] = []
        /// The folder that couldn't be listed whole (unreadable, or the cap); nil when every one was.
        var incomplete: String?
    }

    /// Each of `paths` (relative to `worktree`) that is a real folder without a `.git` entry.
    static func files(in worktree: URL, submodules paths: [String], limit: Int = defaultLimit) -> Result {
        var result = Result()
        var seen = 0
        for submodule in paths {
            let root = worktree.appending(path: submodule, directoryHint: .isDirectory)
            guard DirectoryEntries.kind(ofItemAt: root.path) == .directory,
                  PathPresence.of(root.appending(path: ".git").path) == .missing
            else { continue }
            var pending = [submodule]
            while let folder = pending.popLast() {
                guard let entries = DirectoryEntries.read(worktree.appending(path: folder).path) else {
                    result.incomplete = submodule
                    break
                }
                for entry in entries {
                    seen += 1
                    if seen > limit {
                        result.incomplete = submodule
                        result.files.sort()
                        return result
                    }
                    let path = folder + "/" + entry.name
                    if entry.kind == .directory { pending.append(path) } else { result.files.append(path) }
                }
            }
            if result.incomplete != nil { break }
        }
        result.files.sort()
        return result
    }
}
