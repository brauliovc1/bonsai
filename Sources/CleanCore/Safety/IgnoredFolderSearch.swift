import Foundation

/// Looks inside ignored folders on disk, never descending into regenerable folders (§4.2) or symlinks.
///
/// git collapses a folder that holds only ignored content into one entry (`packages/` for
/// `packages/app/node_modules/`), so the name alone can't say whether it is build output or user files.
/// Each search stops after `limit` entries; a search that can't finish counts as "user files".
struct IgnoredFolderSearch: Sendable {
    var limit: Int

    /// True when `folder` holds a file that is not harmless outside regenerable subfolders, when it can't
    /// be read, or when the search hits its limit.
    func holdsUserFiles(_ folder: URL) -> Bool {
        var pending = [folder]
        var visited = 0
        while let current = pending.popLast() {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: current,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            ) else { return true }
            for child in children {
                visited += 1
                if visited > limit { return true }
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values?.isDirectory == true, values?.isSymbolicLink != true {
                    if !RegenerableNames.isRegenerableFolder(child.lastPathComponent) { pending.append(child) }
                    continue
                }
                if !RegenerableNames.isHarmlessFile(child.lastPathComponent) { return true }
            }
        }
        return false
    }

    /// Folders under `root` (or `root` itself) that contain a `.git` entry: other checkouts.
    func checkouts(in root: URL) -> [URL] {
        let fileManager = FileManager.default
        var found: [URL] = []
        var pending = [root]
        var visited = 0
        while let folder = pending.popLast(), visited < limit {
            if fileManager.fileExists(atPath: folder.appending(path: ".git").path) {
                found.append(folder)
                continue
            }
            let children = (try? fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )) ?? []
            for child in children {
                visited += 1
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values?.isDirectory == true, values?.isSymbolicLink != true,
                      !RegenerableNames.isRegenerableFolder(child.lastPathComponent)
                else { continue }
                pending.append(child)
            }
        }
        return found
    }

    /// Drops entries inside another listed folder entry (`packages/app/` when `packages/` is listed).
    static func topmost(_ entries: [String]) -> [String] {
        let folders = entries.filter { $0.hasSuffix("/") }
        return entries.filter { entry in
            !folders.contains { folder in folder != entry && entry.hasPrefix(folder) }
        }
    }
}
