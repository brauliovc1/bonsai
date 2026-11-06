@testable import CleanCore
import CleanTestSupport
import Foundation

/// A fake DerivedData root in a temp folder, plus a `projects/` folder for workspaces that exist.
///
/// Temp folders are under `/var/folders`, which PLAN §4.4 treats as Xcode's own temp workspaces, so the
/// scanner and cleaner made here don't treat `/var/folders` as internal (`internalPrefixes = []`) unless
/// asked to.
final class DerivedDataWorld: Sendable {
    let directory: TemporaryDirectory

    init() throws {
        directory = try TemporaryDirectory(prefix: "clean-claude-derived-data")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    func remove() {
        directory.remove()
    }

    var root: URL { directory.url.appending(path: "DerivedData", directoryHint: .isDirectory) }
    var projects: URL { directory.url.appending(path: "projects", directoryHint: .isDirectory) }
    var logFolder: URL { directory.url.appending(path: "settings", directoryHint: .isDirectory) }
    /// The home folder the scanner and cleaner are told about (empty).
    var home: URL { directory.url.appending(path: "home", directoryHint: .isDirectory) }
    var log: RemovalLog { RemovalLog(directory: logFolder) }

    /// A project path inside `projects/` (not created).
    func project(_ name: String) -> String {
        CanonicalPath.resolve(projects) + "/" + name
    }

    /// An entry whose `info.plist` names `workspace`, holding `kibibytes` of build output.
    @discardableResult
    func entry(_ name: String, workspace: String, kibibytes: Int = 8) throws -> URL {
        try entry(name, plist: ["WorkspacePath": workspace, "LastAccessedDate": Date(timeIntervalSince1970: 1_790_000_000)], kibibytes: kibibytes)
    }

    @discardableResult
    func entry(_ name: String, plist: [String: Any], kibibytes: Int = 8) throws -> URL {
        let folder = try folder(name, kibibytes: kibibytes)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: folder.appending(path: "info.plist"))
        return folder
    }

    /// An entry with raw `info.plist` bytes.
    @discardableResult
    func entry(_ name: String, rawPlist: String) throws -> URL {
        let folder = try folder(name, kibibytes: 4)
        try Data(rawPlist.utf8).write(to: folder.appending(path: "info.plist"))
        return folder
    }

    /// A folder with `Build/blob` of `kibibytes` KiB and no `info.plist`.
    @discardableResult
    func folder(_ name: String, kibibytes: Int = 4) throws -> URL {
        let folder = root.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "Build"), withIntermediateDirectories: true)
        try Data(count: kibibytes * 1024).write(to: folder.appending(path: "Build/blob"))
        return folder
    }

    func scanner(internalPrefixes: [String] = []) -> DerivedDataScanner {
        var scanner = DerivedDataScanner(root: root, du: URL(fileURLWithPath: "/usr/bin/du"), homeDirectory: home)
        scanner.classifier.internalPrefixes = internalPrefixes
        return scanner
    }

    func cleaner(freeSpace: [Int64?] = [100, 100]) -> DerivedDataCleaner {
        var cleaner = DerivedDataCleaner(log: log, homeDirectory: home)
        cleaner.classifier.internalPrefixes = []
        cleaner.freeSpace = ScriptedFreeSpace(freeSpace).probe
        return cleaner
    }

    func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appending(path: name).path)
    }
}

/// Answers `customDerivedDataLocation` from a fixed value.
struct FakeXcodePreferences: XcodePreferences {
    var value: String?

    func customDerivedDataLocation() async -> String? {
        value
    }
}
