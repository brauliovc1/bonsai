import Foundation

/// Finds main git repos under scan roots (PLAN §3 "Discovery").
///
/// - A root that is itself a repo counts.
/// - Folders are walked to `maxDepth` (root = depth 0).
/// - A folder with a `.git` directory is a main repo: it is recorded and not descended into.
/// - Folders with a `.git` file (linked worktrees, found later through their repo), hidden folders,
///   symlinks, bare repos and `skippedFolderNames` are skipped.
/// - An unreadable folder becomes an issue; the rest of the walk goes on.
public struct RepoDiscovery: Sendable {
    public static let skippedFolderNames: Set<String> = ["node_modules", ".build", "DerivedData", "Pods"]

    public var maxDepth: Int

    public init(maxDepth: Int = 3) {
        self.maxDepth = maxDepth
    }

    public func discover(roots: [URL]) -> DiscoveryResult {
        var walk = Walk()
        for root in roots {
            let root = root.standardized
            guard isDirectory(root) else {
                walk.issues.append(ScanIssue(kind: .rootMissing, path: root.path, message: "scan root is not a folder"))
                continue
            }
            walk.visit(root, depth: 0, maxDepth: maxDepth)
        }
        let repos = walk.repos.values.sorted { $0.path < $1.path }
        return DiscoveryResult(repos: repos, issues: walk.issues)
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

private struct Walk {
    /// Keyed by canonical path, so overlapping roots or a symlinked root report each repo once.
    var repos: [String: URL] = [:]
    var issues: [ScanIssue] = []

    private let fileManager = FileManager.default
    private static let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]

    mutating func visit(_ folder: URL, depth: Int, maxDepth: Int) {
        switch gitEntry(in: folder) {
        case .directory:
            let key = CanonicalPath.resolve(folder)
            if repos[key] == nil, !isBareRepo(folder.appending(path: ".git")) {
                repos[key] = folder
            }
            return
        case .file:
            return
        case .none:
            break
        }
        if isBareRepo(folder) || depth >= maxDepth { return }

        // Names, not URLs: `contentsOfDirectory(at:)` may respell the parent (`/var` -> `/private/var`),
        // and repo paths should keep the spelling of the root they were found under.
        let names: [String]
        do {
            names = try fileManager.contentsOfDirectory(atPath: folder.path)
        } catch {
            issues.append(ScanIssue(kind: .unreadableFolder, path: folder.path, message: Self.reason(error)))
            return
        }

        for name in names.sorted() {
            if name.hasPrefix(".") || RepoDiscovery.skippedFolderNames.contains(name) { continue }
            let child = folder.appending(path: name, directoryHint: .isDirectory)
            guard let values = try? child.resourceValues(forKeys: Self.keys),
                  values.isSymbolicLink != true,
                  values.isDirectory == true
            else { continue }
            visit(child, depth: depth + 1, maxDepth: maxDepth)
        }
    }

    private enum GitEntry { case directory, file }

    /// What `.git` is inside `folder`, without following a symlinked `.git`.
    private func gitEntry(in folder: URL) -> GitEntry? {
        let dotGit = folder.appending(path: ".git")
        guard let attributes = try? fileManager.attributesOfItem(atPath: dotGit.path),
              let type = attributes[.type] as? FileAttributeType
        else { return nil }
        switch type {
        case .typeDirectory: return .directory
        case .typeRegular: return .file
        default: return nil
        }
    }

    /// A bare repo: `HEAD` file plus `objects` and `refs` folders and no work tree. A `.git` directory
    /// counts as bare only when its config says `bare = true`.
    private func isBareRepo(_ folder: URL) -> Bool {
        if folder.lastPathComponent == ".git" {
            guard let config = try? String(contentsOf: folder.appending(path: "config"), encoding: .utf8) else {
                return false
            }
            return config.split(whereSeparator: \.isNewline).contains { line in
                let compact = line.filter { !$0.isWhitespace }.lowercased()
                return compact == "bare=true"
            }
        }
        var isDirectory: ObjCBool = false
        let hasHead = fileManager.fileExists(atPath: folder.appending(path: "HEAD").path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
        return hasHead
            && fileManager.fileExists(atPath: folder.appending(path: "objects").path)
            && fileManager.fileExists(atPath: folder.appending(path: "refs").path)
    }

    private static func reason(_ error: Error) -> String {
        let nsError = error as NSError
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain,
           let code = POSIXErrorCode(rawValue: Int32(underlying.code)) {
            return "cannot read folder (\(String(cString: strerror(code.rawValue))))"
        }
        return "cannot read folder (\(nsError.localizedDescription))"
    }
}
