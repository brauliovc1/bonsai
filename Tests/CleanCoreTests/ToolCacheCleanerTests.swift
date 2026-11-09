@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Tool caches: cleaning")
struct ToolCacheCleanerTests {
    @Test func theCatalogHasEveryEntryOnceWithPathsInsideTheHomeFolder() {
        let ids = ToolCacheCatalog.entries.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ToolCacheCatalog.cleanableIDs == [
            "npm", "yarn", "pip", "uv", "pub", "cocoapods", "homebrew", "gradle", "swiftpm", "go-build", "playwright",
            "mongodb-binaries", "xcode-cache", "cursor-agent-versions", "cursor-state-backup", "cursor-caches",
        ])
        for entry in ToolCacheCatalog.entries {
            #expect(!entry.paths.isEmpty, "\(entry.id)")
            for path in entry.paths + entry.never {
                #expect(!path.hasPrefix("/") && !path.hasPrefix("~") && !path.split(separator: "/").contains(".."), "\(entry.id): \(path)")
            }
            #expect(entry.isCleanable == !entry.owners.isEmpty, "\(entry.id): a cleanable entry has owners, a display-only one none")
            #expect(entry.isCleanable == !entry.targets.isEmpty)
        }
        // The read-only rows are in the catalog with no targets.
        for id in ["cursor-state", "cursor-snapshots", "cursor-workspace-storage", "cursor-chats", "cursor-projects", "cursor-extensions"] {
            #expect(ToolCacheCatalog.entry(id: id)?.targets == [], "\(id)")
        }
        // state.vscdb is never anybody's target.
        #expect(!ToolCacheCatalog.entries.flatMap(\.targets).contains { $0.hasSuffix("state.vscdb") || $0.contains("state.vscdb-") })
    }

    /// Every entry deletes exactly its targets' contents, keeps the target folders, and leaves every "never"
    /// path, the kept versions, Cursor's live database and the display-only rows alone. One log entry each.
    @Test func everyEntryDeletesExactlyItsTargetsContents() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let report = await world.scanner().scan()

        let ready = report.ready
        #expect(Set(ready.map(\.id)) == Set(ToolCacheCatalog.cleanableIDs), "\(report.findings.map { "\($0.id): \($0.verdict)" })")
        #expect(report.findings.filter { if case .displayOnly = $0.verdict { true } else { false } }.count == 6)
        #expect(!report.cursorRunning)
        for finding in report.findings where finding.entry.isCleanable {
            #expect((finding.bytes ?? 0) > 0, "\(finding.id) is measured")
        }
        let versions = try report.require("cursor-agent-versions")
        #expect(versions.removals.map { ($0 as NSString).lastPathComponent } == ToolCacheWorld.oldVersions)
        #expect(Set(versions.kept.map(\.name)) == [ToolCacheWorld.inUseVersion, ToolCacheWorld.newestVersion])

        let result = await world.cleaner().clean(ready)
        #expect(result.refused.isEmpty, "\(result.refused)")
        #expect(result.cleaned.count == ToolCacheCatalog.cleanableIDs.count)
        let failures = result.cleaned.flatMap(\.failures)
        #expect(failures.isEmpty, "\(failures)")

        for path in ToolCacheWorld.removable {
            #expect(!world.exists(path), "\(path) was removed")
        }
        #expect(!world.exists("Library/Caches/Homebrew/wget--1.0.bottle.tar.gz"), "the symlink child went as a link")
        for path in ToolCacheWorld.survivors {
            #expect(world.exists(path), "\(path) survives")
        }
        for entry in ToolCacheCatalog.entries where entry.deletion == .contents {
            for target in entry.targets {
                #expect(world.exists(target) && world.contents(target).isEmpty, "\(target) is kept, empty")
            }
        }
        #expect(world.contents(ToolCacheWorld.versions) == [ToolCacheWorld.inUseVersion, ToolCacheWorld.newestVersion])
        #expect(world.exists(CursorAgentVersions.linkPath))

        // One cacheClean log entry per cleaned entry, written with the estimate and the measured bytes.
        let logged = try world.logEntries()
        #expect(logged == result.entries)
        #expect(logged.map(\.repoPath) == ready.map(\.id))
        for entry in logged {
            let finding = try report.require(entry.repoPath)
            #expect(entry.action == .cacheClean && entry.mode == .manual)
            #expect(entry.estimatedBytes == finding.bytes)
            #expect(entry.freedBytes == 1_048_576)
            #expect(!entry.notes.isEmpty)
        }
        #expect(logged.first { $0.repoPath == "npm" }?.path == world.path(".npm"))
        #expect(logged.first { $0.repoPath == "pip" }?.path == world.path("Library/Caches/pip"))
        #expect(result.freedBytes == Int64(ready.count) * 1_048_576)
        #expect(result.logged)

        // A second scan finds the package caches empty.
        let after = await world.scanner().scan()
        #expect(try after.require("npm").verdict == .empty)
        #expect(try after.require("cursor-agent-versions").verdict == .empty)
        #expect(after.finding(id: "cursor-state-backup") == nil, "the backup is gone, so its row is too")
    }

    /// Entries whose folder is missing are not shown, and cleaning one that vanished after the scan is refused.
    @Test func missingFoldersAreNotShownAndVanishedOnesAreRefused() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        try FileManager.default.removeItem(atPath: world.path("Library/Caches/pip"))
        try FileManager.default.removeItem(atPath: world.path(".cursor"))
        let report = await world.scanner().scan()
        #expect(report.finding(id: "pip") == nil)
        #expect(report.finding(id: "cursor-chats") == nil)
        #expect(report.finding(id: "npm") != nil)

        try FileManager.default.removeItem(atPath: world.path("Library/Caches/go-build"))
        let result = await world.cleaner().clean(try report.require(["go-build", "uv"]))
        #expect(result.refused.map(\.id) == ["go-build"])
        #expect(result.refused.first?.reason == "it no longer exists")
        #expect(result.cleaned.map(\.id) == ["uv"])
        #expect(try world.logEntries().map(\.repoPath) == ["uv"])
    }

    /// Only catalog entries the scan found ready get through.
    @Test func onlyReadyCatalogFindingsAreCleaned() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        world.processes.run("npm install")
        let report = await world.scanner().scan()
        let npm = try report.require("npm")
        #expect(npm.verdict == .refused("Quit npm to clean this"))
        let state = try report.require("cursor-state")

        world.processes.output = ScriptedProcesses.idle
        let result = await world.cleaner().clean([npm, state])
        #expect(result.cleaned.isEmpty)
        #expect(result.refused.map(\.reason) == ["Quit npm to clean this", "cursor-state is not a cleanable catalog entry"])
        #expect(world.exists(".npm/_cacache/index-v5/00/idx"))
        #expect(world.exists(CursorStateBackup.statePath))
        #expect(try world.logEntries().isEmpty)
    }

    /// The app stops the run when it quits: the rest are refused, untouched.
    @Test func aStoppedRunRefusesTheRest() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let report = await world.scanner().scan()
        let asked = CallCounter()
        let result = await world.cleaner().clean(try report.require(["npm", "pip", "uv"])) { asked.next() < 1 }
        #expect(result.cleaned.map(\.id) == ["npm"])
        #expect(result.refused.map(\.id) == ["pip", "uv"])
        #expect(world.exists("Library/Caches/pip/wheels/x.whl"))
    }
}

/// Counts calls across tasks.
private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    /// The count before this call.
    func next() -> Int {
        lock.withLock {
            defer { value += 1 }
            return value
        }
    }
}
