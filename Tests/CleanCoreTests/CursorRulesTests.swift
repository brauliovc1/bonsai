@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Tool caches: Cursor's rules")
struct CursorRulesTests {
    private static let cursorApp = "/Applications/Cursor.app/Contents/MacOS/Cursor"

    /// The link target and the newest version stay; the others go.
    @Test func agentVersionsKeepTheOneInUseAndTheNewest() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let report = await world.scanner().scan()
        let finding = try report.require("cursor-agent-versions")
        #expect(finding.isReady)
        #expect(finding.kept == [
            CursorAgentVersions.Kept(name: ToolCacheWorld.inUseVersion, reason: "the version in use"),
            CursorAgentVersions.Kept(name: ToolCacheWorld.newestVersion, reason: "the newest"),
        ])
        let result = await world.cleaner().clean([finding])
        #expect(result.cleaned.first?.removedCount == 2)
        #expect(world.contents(ToolCacheWorld.versions) == [ToolCacheWorld.inUseVersion, ToolCacheWorld.newestVersion])
        let notes = try world.logEntries().first?.notes ?? []
        #expect(notes.first == "removed versions " + ToolCacheWorld.oldVersions.joined(separator: ", "))
    }

    /// A newer version installed between the scan and the clean makes the old newest removable by the fresh keep
    /// set, but the person never saw it in the confirmation: it stays.
    @Test func onlyVersionsTheConfirmationListedGo() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let finding = try await world.scanner().scan().require("cursor-agent-versions")
        try world.home.addFile(ToolCacheWorld.versions + "/2026.10.25-1a2b3c4/cursor-agent", kibibytes: 4)
        let result = await world.cleaner().clean([finding])
        #expect(result.cleaned.first?.removedCount == 2)
        #expect(world.contents(ToolCacheWorld.versions) == [ToolCacheWorld.inUseVersion, ToolCacheWorld.newestVersion, "2026.10.25-1a2b3c4"])
    }

    /// "By name" compares numbers as numbers, and one version that is both in use and newest is kept once.
    @Test func newestIsByNumberAndCanBeTheOneInUse() throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        try world.home.addFile(ToolCacheWorld.versions + "/2026.9.30-zzz/cursor-agent", kibibytes: 4)
        try world.home.addFile(ToolCacheWorld.versions + "/.staging-2027/cursor-agent", kibibytes: 4)
        let link = world.path(CursorAgentVersions.linkPath)
        try FileManager.default.removeItem(atPath: link)
        try FileManager.default.createSymbolicLink(
            atPath: link, withDestinationPath: "../share/cursor-agent/versions/\(ToolCacheWorld.newestVersion)/cursor-agent"
        )
        guard case .resolved(let versions) = CursorAgentVersions.resolve(home: world.url) else {
            Issue.record("a relative link into versions/ resolves")
            return
        }
        #expect(versions.kept == [CursorAgentVersions.Kept(name: ToolCacheWorld.newestVersion, reason: "the version in use and the newest")])
        #expect(versions.removable == ToolCacheWorld.oldVersions + ["2026.9.30-zzz", ToolCacheWorld.inUseVersion],
                "2026.9.30 sorts before 2026.10.x; hidden folders are left alone")
    }

    /// A link that is missing, dangling or points anywhere but into a version folder refuses the entry whole.
    @Test(arguments: ["missing", "dangling", "outside", "versions folder", "file"])
    func aBadLinkRefusesTheWholeEntry(kind: String) async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let link = world.path(CursorAgentVersions.linkPath)
        try FileManager.default.removeItem(atPath: link)
        let expected: String
        switch kind {
        case "missing":
            expected = "the cursor-agent link (~/\(CursorAgentVersions.linkPath)) is missing, so the version in use is unknown"
        case "dangling":
            try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: world.path(ToolCacheWorld.versions + "/gone/cursor-agent"))
            expected = "the cursor-agent link points to something that doesn't exist (\(world.path(ToolCacheWorld.versions + "/gone/cursor-agent")))"
        case "outside":
            try world.home.addFile("elsewhere/cursor-agent", kibibytes: 4)
            try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: world.path("elsewhere/cursor-agent"))
            expected = "the cursor-agent link points outside the versions folder (\(world.path("elsewhere/cursor-agent")))"
        case "versions folder":
            try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: world.path(ToolCacheWorld.versions))
            expected = "the cursor-agent link points outside the versions folder (\(world.path(ToolCacheWorld.versions)))"
        default:
            try world.home.addFile(CursorAgentVersions.linkPath, kibibytes: 4)
            expected = "~/\(CursorAgentVersions.linkPath) is not a symbolic link"
        }
        let report = await world.scanner().scan()
        let finding = try report.require("cursor-agent-versions")
        #expect(finding.verdict == .refused(expected))
        #expect(finding.removals.isEmpty)
        _ = await world.cleaner().clean([finding])
        #expect(world.contents(ToolCacheWorld.versions).count == 4, "no version was touched")
    }

    /// Cursor or any cursor-agent running refuses the versions; Cursor running refuses all three entries.
    @Test(arguments: [
        ("/Applications/Cursor.app/Contents/MacOS/Cursor", "Cursor"),
        ("/Applications/Cursor.app/Contents/Frameworks/Cursor Helper (Renderer).app/Contents/MacOS/Cursor Helper (Renderer) --type=renderer", "Cursor"),
        ("/Users/me/.local/bin/cursor-agent --print", "cursor-agent"),
        ("/Users/me/Applications/Cursor 2.app/Contents/MacOS/Cursor", "Cursor"),
    ])
    func cursorRunningRefusesItsEntries(line: String, owner: String) async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        world.processes.run(line)
        let report = await world.scanner().scan()
        #expect(try report.require("cursor-agent-versions").verdict == .refused("Quit \(owner) to clean this"))
        if owner == "Cursor" {
            #expect(report.cursorRunning)
            #expect(try report.require("cursor-state-backup").verdict == .refused("Quit Cursor to clean this"))
            #expect(try report.require("cursor-caches").verdict == .refused("Quit Cursor to clean this"))
        }
        #expect(try report.require("npm").isReady)
    }

    /// The app's NSWorkspace answer counts as Cursor running even when ps doesn't show it.
    @Test func theAppsBundleCheckCountsToo() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        world.processes.cursorAppRunning = true
        let report = await world.scanner().scan()
        #expect(report.cursorRunning)
        #expect(try report.require("cursor-caches").verdict == .refused("Quit Cursor to clean this"))
    }

    /// A version whose `.running` folder names a live process stays; one naming only ended processes goes.
    @Test func aRunningMarkerKeepsItsVersion() throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let (live, ended) = (ToolCacheWorld.oldVersions[0], ToolCacheWorld.oldVersions[1])
        try world.home.addFile(ToolCacheWorld.versions + "/\(live)/.running/4242", kibibytes: 0)
        try world.home.addFile(ToolCacheWorld.versions + "/\(ended)/.running/4343", kibibytes: 0)
        guard case .resolved(let versions) = CursorAgentVersions.resolve(home: world.url, isAlive: { $0 == 4242 }) else {
            Issue.record("resolves")
            return
        }
        #expect(versions.removable == [ended])
        #expect(versions.kept.first { $0.name == live }?.reason == "process 4242 is using it")
        try world.home.addFile(ToolCacheWorld.versions + "/\(ended)/.running/not-a-pid", kibibytes: 0)
        guard case .resolved(let again) = CursorAgentVersions.resolve(home: world.url, isAlive: { _ in false }) else { return }
        #expect(again.removable == [live])
    }

    /// The backup is offered at 7+ days with a non-empty state.vscdb, and not when younger, missing or empty.
    @Test(arguments: ["old", "young", "no state", "empty state", "state is a link"])
    func theBackupRule(kind: String) async throws {
        let now = Date()
        let world = try ToolCacheWorld(now: now, backupAgeDays: kind == "young" ? 6.9 : 7.01)
        defer { world.remove() }
        let state = world.path(CursorStateBackup.statePath)
        switch kind {
        case "no state": try FileManager.default.removeItem(atPath: state)
        case "empty state": try Data().write(to: URL(fileURLWithPath: state))
        case "state is a link":
            try FileManager.default.removeItem(atPath: state)
            try FileManager.default.createSymbolicLink(atPath: state, withDestinationPath: world.path(CursorStateBackup.statePath + "-wal"))
        default: break
        }
        let report = await world.scanner().scan()
        let finding = try report.require("cursor-state-backup")
        switch kind {
        case "old":
            #expect(finding.isReady)
            #expect(finding.note.hasPrefix("Cursor's spare copy from ") && finding.note.hasSuffix("your current chats stay in `state.vscdb`."))
        case "young": #expect(finding.verdict == .refused("it's only 6 days old; Cursor may still need it"))
        case "no state": #expect(finding.verdict == .refused("state.vscdb is missing, so this backup may be the only copy of your chats"))
        case "empty state": #expect(finding.verdict == .refused("state.vscdb is empty, so this backup may be the only copy of your chats"))
        default: #expect(finding.verdict == .refused("state.vscdb is not a plain file, so this backup may be the only copy of your chats"))
        }
        #expect((finding.bytes ?? 0) > 0, "its size shows either way")
    }

    /// Refused when Cursor runs, also when Cursor starts after the scan; and a replaced backup is left alone.
    @Test func theBackupWaitsForCursorAndForTheSameFile() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let report = await world.scanner().scan()
        let finding = try report.require("cursor-state-backup")
        world.processes.run(Self.cursorApp)
        var result = await world.cleaner().clean([finding])
        #expect(result.refused.first?.reason == "Quit Cursor to clean this")
        #expect(world.exists(CursorStateBackup.backupPath))

        world.processes.output = ScriptedProcesses.idle
        let backup = world.path(CursorStateBackup.backupPath)
        try FileManager.default.removeItem(atPath: backup)
        try Data(count: 4096).write(to: URL(fileURLWithPath: backup))
        try world.setBackupAge(days: 40)
        result = await world.cleaner().clean([finding])
        #expect(result.refused.first?.reason == "the backup was replaced since it was confirmed")
        #expect(world.exists(CursorStateBackup.backupPath))
        for path in [CursorStateBackup.statePath, CursorStateBackup.statePath + "-wal", CursorStateBackup.statePath + "-shm"] {
            #expect(world.exists(path))
        }
    }
}
