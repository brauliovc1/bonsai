import Foundation

/// Copies only metadata needed to read a checkout. It never links writable files back into the repo.
enum CompareGitView {
    struct Location { let root: URL; let git: URL; let common: URL }

    static func locate(_ folder: URL) throws -> Location {
        let fm = FileManager.default
        var root = folder.standardizedFileURL.resolvingSymlinksInPath()
        while root.path != "/" {
            let dot = root.appending(path: ".git")
            var directory: ObjCBool = false
            if fm.fileExists(atPath: dot.path, isDirectory: &directory) {
                let git: URL
                if directory.boolValue { git = dot }
                else {
                    let text = try String(contentsOf: dot, encoding: .utf8)
                    guard text.hasPrefix("gitdir: ") else { throw CompareError("The checkout's .git file could not be read.") }
                    git = path(String(text.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: root)
                }
                let commonFile = git.appending(path: "commondir")
                let common = fm.fileExists(atPath: commonFile.path)
                    ? path(try String(contentsOf: commonFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: git) : git
                return Location(root: root, git: git, common: common)
            }
            root.deleteLastPathComponent()
        }
        throw CompareError("Choose a folder inside a Git checkout.")
    }

    static func make(at target: URL, location: Location) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: target.appending(path: "objects"), withIntermediateDirectories: true)
        try fm.createDirectory(at: target.appending(path: "refs"), withIntermediateDirectories: true)
        // No copied config: filters, includes, external diff, merge drivers, hooks and fsmonitor stay out.
        let config = safeConfig(in: location.common)
            + BranchTrackingConfig.sanitized(common: location.common, worktree: location.git)
        try Data(config.utf8).write(to: target.appending(path: "config"))
        for name in ["HEAD", "index"] { try copyFile(location.git.appending(path: name), to: target.appending(path: name)) }
        for name in ["packed-refs", "shallow", "info/exclude"] {
            try copyFile(location.common.appending(path: name), to: target.appending(path: name))
        }
        try copyTree(location.common.appending(path: "refs"), to: target.appending(path: "refs"))
        try copyTree(location.common.appending(path: "logs"), to: target.appending(path: "logs"))
        try copyTree(location.common.appending(path: "reftable"), to: target.appending(path: "reftable"))
        if !CanonicalPath.same(location.git, location.common) {
            try copyFile(location.git.appending(path: "logs/HEAD"), to: target.appending(path: "logs/HEAD"))
        }
        for name in (try? fm.contentsOfDirectory(atPath: location.git.path)) ?? [] where name.hasPrefix("sharedindex.") {
            try copyFile(location.git.appending(path: name), to: target.appending(path: name))
        }
    }

    /// Only data-format and filesystem settings cross the boundary. Includes and command settings never do.
    private static func safeConfig(in directory: URL) -> String {
        let text = (try? String(contentsOf: directory.appending(path: "config"), encoding: .utf8)) ?? ""
        var section = ""; var values: [String: String] = [:]
        let allowed: [String: Set<String>] = [
            "core.filemode": ["true", "false"], "core.ignorecase": ["true", "false"],
            "core.symlinks": ["true", "false"], "extensions.objectformat": ["sha1", "sha256"],
            "extensions.refstorage": ["files", "reftable"],
        ]
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), let end = line.firstIndex(of: "]") {
                section = String(line[line.index(after: line.startIndex)..<end]).lowercased(); continue
            }
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = section + "." + parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces).lowercased()
            if allowed[key]?.contains(value) == true { values[key] = value }
        }
        var result = "[core]\nrepositoryformatversion = \(values.keys.contains(where: { $0.hasPrefix("extensions.") }) ? 1 : 0)\nbare = false\nattributesFile = /dev/null\n[diff]\nrenames = true\n"
        for key in values.keys.sorted() {
            let parts = key.split(separator: ".")
            result += "[\(parts[0])]\n\(parts[1]) = \(values[key]!)\n"
        }
        return result
    }

    private static func copyTree(_ source: URL, to target: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return }
        guard let files = fm.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            throw CompareError("Git metadata could not be read.")
        }
        for case let file as URL in files {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isRegularFile == true || values.isSymbolicLink == true {
                guard let relative = CanonicalPath.relativePath(of: file, to: source) else { throw CompareError("A Git metadata link points outside its folder.") }
                try copyFile(file, to: target.appending(path: relative))
            }
        }
    }

    private static func copyFile(_ source: URL, to target: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let bytes = try Data(contentsOf: source)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: target)
    }

    private static func path(_ path: String, relativeTo folder: URL) -> URL {
        (path.hasPrefix("/") ? URL(fileURLWithPath: path) : folder.appending(path: path)).standardizedFileURL
    }

    /// Git's alternates syntax uses C quoting for paths containing colons or quotes.
    static func quotedAlternate(_ path: String) -> String {
        "\"" + path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t") + "\""
    }
}
