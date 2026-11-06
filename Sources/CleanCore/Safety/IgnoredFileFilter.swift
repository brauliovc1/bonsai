import Foundation

/// Turns the entries of `git ls-files --others --ignored --exclude-standard --directory` into the ignored
/// user files of PLAN §4.1: everything except §4.2 build output.
///
/// An entry is harmless when
/// - its own name is in §4.2 (a regenerable folder, or a harmless file name), or
/// - it is inside a folder named in §4.2 that git tracks nothing in. `.ruff_cache`, `.pytest_cache` and
///   `.mypy_cache` write their own `.gitignore` with `*`, so git lists their files one by one; or
/// - it is a collapsed folder (git lists `packages/` when everything in it is ignored) holding nothing but
///   §4.2 output (`IgnoredFolderSearch`).
struct IgnoredFileFilter {
    var git: Git
    var folder: URL
    var searchLimit: Int

    func userFiles(_ entries: [String]) async -> [String] {
        let search = IgnoredFolderSearch(limit: searchLimit)
        var tracksNothing: [String: Bool] = [:]
        var userFiles: [String] = []

        for entry in entries {
            if RegenerableNames.isHarmlessIgnoredPath(entry) { continue }
            var insideOutput = false
            for ancestor in Self.regenerableAncestors(of: entry) {
                if tracksNothing[ancestor] == nil {
                    tracksNothing[ancestor] = await isUntracked(ancestor)
                }
                if tracksNothing[ancestor] == true {
                    insideOutput = true
                    break
                }
            }
            if insideOutput { continue }
            if entry.hasSuffix("/"), !search.holdsUserFiles(folder.appending(path: entry, directoryHint: .isDirectory)) {
                continue
            }
            userFiles.append(entry)
        }
        return IgnoredFolderSearch.topmost(userFiles)
    }

    /// The folders above `entry` whose own name is in §4.2, outermost first: `a/.ruff_cache/0.1/x` ->
    /// `["a/.ruff_cache"]`.
    static func regenerableAncestors(of entry: String) -> [String] {
        let parts = entry.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count > 1 else { return [] }
        var ancestors: [String] = []
        for index in 0..<(parts.count - 1) where RegenerableNames.isRegenerableFolder(parts[index]) {
            ancestors.append(parts[...index].joined(separator: "/"))
        }
        return ancestors
    }

    /// git tracks nothing in the folder: `git ls-files -z` run inside it is empty. Run inside rather than with
    /// a pathspec, so the folder's name never passes through `Process` (which decomposes non-ASCII
    /// arguments; see `Remover.removeCommand`). A git failure counts as "tracked" (not harmless).
    private func isUntracked(_ relativeFolder: String) async -> Bool {
        let inside = folder.appending(path: relativeFolder, directoryHint: .isDirectory)
        guard let output = try? await git.git(["ls-files", "-z"], in: inside) else { return false }
        return output.isEmpty
    }
}
