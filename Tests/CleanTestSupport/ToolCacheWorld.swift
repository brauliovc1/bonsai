import CleanCore
import Foundation

/// A fake home in the temp folder with a small tree for every tool-cache catalog entry (PLAN §4.6), the files
/// each entry must leave alone, and scripted ps output (`processes`, idle at first). Keep it alive for the
/// whole test (`defer { world.remove() }`).
public final class ToolCacheWorld: Sendable {
    public static let versions = CursorAgentVersions.versionsPath
    public static let inUseVersion = "2026.10.18-ea085cb"
    public static let newestVersion = "2026.10.19-6bbf2c4"
    public static let oldVersions = ["2026.08.25-3e8eec8", "2026.09.02-c22c1a3"]
    static let cursor = "Library/Application Support/Cursor"
    static let globalStorage = cursor + "/User/globalStorage"

    /// Files inside the targets: cleaning every entry removes all of them.
    public static let removable = [
        ".npm/_cacache/content-v2/sha512/ab/cd/blob", ".npm/_cacache/index-v5/00/idx", ".npm/_npx/abc123/node_modules/pkg/index.js",
        "Library/Caches/Yarn/v6/npm-left-pad/index.js", ".yarn/berry/cache/left-pad.zip",
        "Library/Caches/pip/http-v2/a/b", "Library/Caches/pip/wheels/x.whl",
        ".pub-cache/hosted/pub.dev/http-1.0.0/lib/http.dart",
        "Library/Caches/CocoaPods/Pods/Release/Alamofire/x",
        "Library/Caches/Homebrew/downloads/abc--wget--1.0.bottle.tar.gz",
        ".gradle/caches/modules-2/files-2.1/x.jar",
        "Library/Caches/org.swift.swiftpm/repositories/swift-argument-parser/HEAD",
        "Library/Caches/go-build/00/00aa-d", "Library/Caches/go-build/trim.txt",
        "Library/Caches/ms-playwright/chromium-1140/chrome-mac/Chromium",
        ".cache/mongodb-binaries/mongod-arm64-darwin-7.0.24",
        "Library/Caches/com.apple.dt.Xcode/Cache.db",
        CursorStateBackup.backupPath,
        cursor + "/Cache/Cache_Data/f_000001", cursor + "/CachedData/abc/x", cursor + "/Code Cache/js/x",
        cursor + "/GPUCache/data_0", cursor + "/CachedExtensionVSIXs/ext.vsix", cursor + "/logs/20261108T100000/main.log",
    ] + oldVersions.map { versions + "/" + $0 + "/cursor-agent" }

    /// Files and folders no cleaning may touch: every "never" path, the target folders themselves, the kept
    /// versions and the link, Cursor's live database and what is display-only.
    public static let survivors = [
        ".npm/_logs/2026-11-08-debug.log", ".npm/_update-notifier-last-checked", ".npm/_prebuilds/libvips.tgz",
        ".yarn/berry/install-state.gz", ".cache/gh/hosts.yml", ".cache/uv/archive-v0/x",
        ".pub-cache/bin/tool", ".pub-cache/global_packages/tool/pubspec.lock", ".pub-cache/README.md",
        ".pub-cache/git/cache/repo/HEAD",
        ".gradle/gradle.properties", ".gradle/wrapper/dists/gradle-8.5-bin/gradle.zip",
        "Library/Caches/com.apple.Safari/Cache.db",
        CursorStateBackup.statePath, CursorStateBackup.statePath + "-wal", CursorStateBackup.statePath + "-shm",
        globalStorage + "/storage.json", cursor + "/User/settings.json", cursor + "/Preferences",
        cursor + "/snapshots/roots/x", cursor + "/User/workspaceStorage/abc/state.vscdb",
        ".cursor/chats/c1.json", ".cursor/projects/p1/x", ".cursor/extensions/e1/package.json", ".cursor/worktrees/w/file",
        versions + "/" + inUseVersion + "/cursor-agent", versions + "/" + newestVersion + "/cursor-agent",
    ]

    public let home: FakeHome
    public let processes: ScriptedProcesses

    /// `backupAgeDays`: how old Cursor's `state.vscdb.backup` is.
    public init(now: Date = Date(), backupAgeDays: Double = 30) throws {
        home = try FakeHome()
        processes = ScriptedProcesses()
        for path in Self.removable + Self.survivors {
            try home.addFile(path, kibibytes: 4)
        }
        // Homebrew keeps a symlink next to each download; cleaning removes the link, not what it names.
        try FileManager.default.createSymbolicLink(
            atPath: url.appending(path: "Library/Caches/Homebrew/wget--1.0.bottle.tar.gz").path,
            withDestinationPath: "downloads/abc--wget--1.0.bottle.tar.gz"
        )
        try home.addFolder((CursorAgentVersions.linkPath as NSString).deletingLastPathComponent)
        try FileManager.default.createSymbolicLink(
            atPath: url.appending(path: CursorAgentVersions.linkPath).path,
            withDestinationPath: url.appending(path: Self.versions + "/" + Self.inUseVersion + "/cursor-agent").path
        )
        try writeState(kibibytes: 4)
        try setBackupAge(days: backupAgeDays, now: now)
    }

    /// Cursor's `state.vscdb` as an SQLite file of `kibibytes` KiB (the header, then zeros).
    public func writeState(kibibytes: Int) throws {
        var data = Data("SQLite format 3\u{0}".utf8)
        data.append(Data(count: max(0, kibibytes * 1024 - data.count)))
        try data.write(to: URL(fileURLWithPath: path(CursorStateBackup.statePath)))
    }

    /// Replaces the backup with `kibibytes` KiB of zeros, `days` old.
    public func writeBackup(kibibytes: Int, days: Double = 30) throws {
        try Data(count: kibibytes * 1024).write(to: URL(fileURLWithPath: path(CursorStateBackup.backupPath)))
        try setBackupAge(days: days)
    }

    public var url: URL { home.url }

    /// Home, settings and the Claude folders all inside the fake home; the real `du`.
    public var environment: CleanEnvironment { home.environment() }

    public func remove() {
        home.remove()
    }

    public func path(_ relative: String) -> String {
        url.appending(path: relative).path
    }

    /// Something is at `relative` (a dangling link counts).
    public func exists(_ relative: String) -> Bool {
        var info = stat()
        return lstat(path(relative), &info) == 0
    }

    /// The names inside a folder.
    public func contents(_ relative: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: path(relative))) ?? []).sorted()
    }

    public func setBackupAge(days: Double, now: Date = Date()) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-days * 86_400)],
            ofItemAtPath: path(CursorStateBackup.backupPath)
        )
    }

    /// Replaces the folder at `relative` with a symlink to a copy of it elsewhere in the temp folder; returns the
    /// copy, which must survive whatever the test does.
    @discardableResult
    public func replaceWithLink(_ relative: String) throws -> URL {
        let outside = FileManager.default.temporaryDirectory.appending(path: "clean-claude-outside-\(UUID().uuidString)")
        try FileManager.default.moveItem(atPath: path(relative), toPath: outside.path)
        try FileManager.default.createSymbolicLink(atPath: path(relative), withDestinationPath: outside.path)
        return outside
    }
}
