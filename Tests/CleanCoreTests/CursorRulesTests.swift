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

    /// Review item 3, probe `probeNewestByNameCanBeAStrayFolder`: only dated names are versions. `latest` or a
    /// `.partial` download sorts after every version by name but is never the newest and never deleted.
    @Test func foldersThatAreNotVersionsAreNeverNewestOrRemoved() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        for name in ["latest", "2026.11.01-abcdef0.partial", "2026.11.01", "2026.11.01-XYZ", "zzz-tmp"] {
            try world.home.addFile(ToolCacheWorld.versions + "/\(name)/cursor-agent", kibibytes: 4)
        }
        let finding = try await world.scanner().scan().require("cursor-agent-versions")
        #expect(finding.kept.first { $0.reason.contains("the newest") }?.name == ToolCacheWorld.newestVersion)
        #expect(finding.removals.map { ($0 as NSString).lastPathComponent } == ToolCacheWorld.oldVersions)
        _ = await world.cleaner().clean([finding])
        for name in ["latest", "2026.11.01-abcdef0.partial", "2026.11.01", "2026.11.01-XYZ", "zzz-tmp", ToolCacheWorld.newestVersion] {
            #expect(world.exists(ToolCacheWorld.versions + "/" + name), "\(name) stays")
        }
    }

    /// Review item 3: two versions of the same day: the more recently modified one is the newest.
    @Test func sameDayVersionsGoByModificationDate() throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let (older, newer) = ("2026.10.25-fff0000", "2026.10.25-0000aaa")
        for (name, daysAgo) in [(older, 2.0), (newer, 1.0)] {
            try world.home.addFile(ToolCacheWorld.versions + "/\(name)/cursor-agent", kibibytes: 4)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-daysAgo * 86_400)],
                                                  ofItemAtPath: world.path(ToolCacheWorld.versions + "/" + name))
        }
        guard case .resolved(let versions) = CursorAgentVersions.resolve(home: world.url) else {
            Issue.record("resolves")
            return
        }
        #expect(versions.kept.first { $0.reason == "the newest" }?.name == newer, "not \"fff0000\", which wins by name")
        #expect(versions.removable.contains(older))
    }

    /// Review item 3, probe `probeLinkHopThroughAnotherVersion`: the link names version X whose cursor-agent is itself
    /// a link into version Y. X (named directly) and Y (where the chain ends) both stay, and the link still resolves
    /// after the clean.
    @Test func aChainedLinkKeepsBothVersions() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let named = ToolCacheWorld.oldVersions[1]
        let real = ToolCacheWorld.inUseVersion
        let namedAgent = world.path(ToolCacheWorld.versions + "/\(named)/cursor-agent")
        try FileManager.default.removeItem(atPath: namedAgent)
        try FileManager.default.createSymbolicLink(atPath: namedAgent, withDestinationPath: "../\(real)/cursor-agent")
        let link = world.path(CursorAgentVersions.linkPath)
        try FileManager.default.removeItem(atPath: link)
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: namedAgent)

        let finding = try await world.scanner().scan().require("cursor-agent-versions")
        #expect(finding.kept == [
            CursorAgentVersions.Kept(name: named, reason: "the version the cursor-agent link names"),
            CursorAgentVersions.Kept(name: real, reason: "the version in use"),
            CursorAgentVersions.Kept(name: ToolCacheWorld.newestVersion, reason: "the newest"),
        ])
        let result = await world.cleaner().clean([finding])
        #expect(result.cleaned.first?.removedCount == 1)
        #expect(realpath(link, nil) != nil, "the link still resolves")
        #expect(world.contents(ToolCacheWorld.versions) == [named, real, ToolCacheWorld.newestVersion])
    }

    /// Review item 6: when fewer versions go than were confirmed, the log entry carries the estimate of the ones
    /// that went, not the scan's total.
    @Test func theLogEstimateIsOfWhatWasRemoved() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        try world.home.addFile(ToolCacheWorld.versions + "/\(ToolCacheWorld.oldVersions[0])/node", kibibytes: 400)
        let finding = try await world.scanner().scan().require("cursor-agent-versions")
        let kept = world.path(ToolCacheWorld.versions + "/" + ToolCacheWorld.oldVersions[1])
        let stays = try #require(finding.removalBytes[kept])
        let goes = try #require(finding.removalBytes[world.path(ToolCacheWorld.versions + "/" + ToolCacheWorld.oldVersions[0])])
        #expect(finding.bytes == stays + goes)
        // A live process now runs the second old version, so the fresh keep set keeps it.
        try world.home.addFile(ToolCacheWorld.versions + "/\(ToolCacheWorld.oldVersions[1])/.running/\(getpid())", kibibytes: 0)

        let result = await world.cleaner().clean([finding])
        #expect(result.cleaned.first?.removedCount == 1)
        #expect(result.cleaned.first?.estimatedBytes == goes)
        #expect(try world.logEntries().first?.estimatedBytes == goes)
        #expect(world.exists(ToolCacheWorld.versions + "/" + ToolCacheWorld.oldVersions[1]))
    }

    /// "By name" compares numbers as numbers, and one version that is both in use and newest is kept once.
    @Test func newestIsByNumberAndCanBeTheOneInUse() throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        try world.home.addFile(ToolCacheWorld.versions + "/2026.9.30-abc1234/cursor-agent", kibibytes: 4)
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
        #expect(versions.removable == ToolCacheWorld.oldVersions + ["2026.9.30-abc1234", ToolCacheWorld.inUseVersion],
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

    /// Review item 1: the backup is offered only at 7+ days with a state.vscdb that starts with the SQLite header and
    /// is at least half the backup's size; a 1-byte, a non-SQLite or a 40 % state keeps it.
    @Test(arguments: ["old", "young", "no state", "one byte", "not sqlite", "40 percent", "60 percent", "half", "state is a link"])
    func theBackupRule(kind: String) async throws {
        let now = Date()
        let world = try ToolCacheWorld(now: now, backupAgeDays: kind == "young" ? 6.9 : 7.01)
        defer { world.remove() }
        let state = world.path(CursorStateBackup.statePath)
        let chats = CursorStateBackup.mayHoldChats
        try world.writeBackup(kibibytes: 100, days: kind == "young" ? 6.9 : 7.01)
        try world.writeState(kibibytes: 100)
        switch kind {
        case "no state": try FileManager.default.removeItem(atPath: state)
        case "one byte": try Data([0x53]).write(to: URL(fileURLWithPath: state))
        case "not sqlite": try Data(count: 100 * 1024).write(to: URL(fileURLWithPath: state))
        case "40 percent": try world.writeState(kibibytes: 40)
        case "60 percent": try world.writeState(kibibytes: 60)
        case "half": try world.writeState(kibibytes: 50)
        case "state is a link":
            try FileManager.default.removeItem(atPath: state)
            try FileManager.default.createSymbolicLink(atPath: state, withDestinationPath: world.path(CursorStateBackup.statePath + "-wal"))
        default: break
        }
        let report = await world.scanner().scan()
        let finding = try report.require("cursor-state-backup")
        switch kind {
        case "old", "60 percent", "half":
            #expect(finding.isReady, "\(finding.verdict)")
            #expect(finding.note.hasPrefix("Cursor's spare copy from ") && finding.note.hasSuffix("your current chats stay in `state.vscdb`."))
        case "young": #expect(finding.verdict == .refused("it's only 6 days old; Cursor may still need it"))
        case "no state": #expect(finding.verdict == .refused(chats + " (state.vscdb is missing)"))
        case "one byte", "not sqlite": #expect(finding.verdict == .refused(chats + " (state.vscdb is not an SQLite database)"))
        case "40 percent": #expect(finding.verdict == .refused(chats + " (state.vscdb is 40% of the backup's size)"))
        default: #expect(finding.verdict == .refused(chats + " (state.vscdb is not a plain file)"))
        }
        #expect((finding.bytes ?? 0) > 0, "its size shows either way")
        // The cleaner decides again: a refused backup is never removed.
        _ = await world.cleaner().clean([finding])
        #expect(world.exists(CursorStateBackup.backupPath) == !finding.isReady)
    }

    /// Review item 1, probe `probeBackupWithTinyState`: a state.vscdb that shrank to 1 byte after the scan keeps the
    /// backup at clean time.
    @Test func aStateThatShrinksAfterTheScanKeepsTheBackup() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let finding = try await world.scanner().scan().require("cursor-state-backup")
        #expect(finding.isReady)
        try Data([0x53]).write(to: URL(fileURLWithPath: world.path(CursorStateBackup.statePath)))
        let result = await world.cleaner().clean([finding])
        #expect(result.refused.first?.reason == CursorStateBackup.mayHoldChats + " (state.vscdb is not an SQLite database)")
        #expect(world.exists(CursorStateBackup.backupPath))
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
