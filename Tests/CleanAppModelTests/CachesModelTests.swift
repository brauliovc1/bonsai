@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Tool caches model")
@MainActor
struct CachesModelTests {
    private static let packageIDs = [
        "npm", "yarn", "pip", "uv", "pub", "cocoapods", "homebrew", "gradle", "swiftpm", "go-build", "playwright",
        "mongodb-binaries", "xcode-cache",
    ]

    private func makeModel(_ world: ToolCacheWorld) -> CachesModel {
        CachesModel(app: AppModel(environment: world.environment), processes: world.processes.source)
    }

    @Test func rowsComeBySectionAndOnlyReadyOnesCanBeSelected() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let model = makeModel(world)
        await model.refresh()

        #expect(model.rows(in: .packages).map(\.id) == Self.packageIDs)
        #expect(model.rows(in: .cursor).map(\.id) == [
            "cursor-agent-versions", "cursor-state-backup", "cursor-caches",
            "cursor-state", "cursor-snapshots", "cursor-workspace-storage", "cursor-chats", "cursor-projects", "cursor-extensions",
        ])
        let displayOnly = model.allRows.filter(\.isDisplayOnly)
        #expect(displayOnly.count == 6)
        #expect(displayOnly.allSatisfy { !$0.isSelectable && $0.tone == .displayOnly })
        #expect(displayOnly.first { $0.id == "cursor-state" }?.statusText == "Your chats and settings")
        #expect(displayOnly.first { $0.id == "cursor-snapshots" }?.statusText == "Cursor's checkpoints")

        let npm = try #require(model.allRows.first { $0.id == "npm" })
        #expect(npm.statusText == "Ready" && npm.tone == .ready)
        #expect(npm.folderText == "~/.npm: _cacache, _npx")
        #expect(npm.sizeText != "–")
        #expect(model.allRows.first { $0.id == "pip" }?.folderText == "~/Library/Caches/pip")
        #expect(model.allRows.first { $0.id == "yarn" }?.folderText == "~/Library/Caches/Yarn, ~/.yarn/berry/cache")
        #expect(model.allRows.first { $0.id == "cursor-agent-versions" }?.keptText
            == "Keeps \(ToolCacheWorld.inUseVersion) (the version in use), \(ToolCacheWorld.newestVersion) (the newest)")

        model.setSelected("cursor-state", true)
        #expect(model.selection.isEmpty, "a display-only row is never selected")
        model.setSelected("npm", true)
        #expect(model.selectedRows.map(\.id) == ["npm"])
        #expect(model.canClean)
        model.selectAllReady()
        #expect(model.selectedRows.count == 16)
        #expect(model.readyBytes == model.selectedBytes)
        #expect(model.cursorRunningLine == nil)
    }

    @Test func aRunningToolSaysWhatToQuitAndLeavesTheSelection() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let model = makeModel(world)
        await model.refresh()
        model.selectAllReady()

        world.processes.run("npm install", "/Applications/Cursor.app/Contents/MacOS/Cursor")
        await model.refresh()
        let npm = try #require(model.allRows.first { $0.id == "npm" })
        #expect(npm.tone == .waiting && npm.statusText == "Quit npm to clean this" && !npm.isSelectable)
        #expect(model.cursorRunningLine == "Quit Cursor to clean its data.")
        #expect(model.rows(in: .cursor).filter { !$0.isDisplayOnly }.allSatisfy { $0.statusText == "Quit Cursor to clean this" })
        #expect(!model.selection.contains("npm"), "a row that can't be cleaned now drops out of the selection")
        #expect(!model.selection.contains("cursor-caches"))
        #expect(model.selection.contains("pip"))
    }

    /// cleanSelected() cleans exactly the selection, logs one entry each, and scans again.
    @Test func cleanSelectedCleansTheSelectionAndLogsEachEntry() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let model = makeModel(world)
        await model.refresh()
        model.setSelected("npm", true)
        model.setSelected("cursor-state-backup", true)

        let report = await model.cleanSelected()
        #expect(report.cleanedCount == 2 && report.notCleanedCount == 0)
        #expect(report.summary.hasPrefix("Cleaned 2 items"))
        #expect(!world.exists(".npm/_cacache/index-v5/00/idx"))
        #expect(!world.exists(CursorStateBackup.backupPath))
        #expect(world.exists(CursorStateBackup.statePath))
        #expect(world.exists("Library/Caches/pip/wheels/x.whl"), "not selected, not touched")
        #expect(model.app.logEntries.map(\.repoPath) == ["npm", "cursor-state-backup"])
        #expect(model.app.logEntries.allSatisfy { $0.action == .cacheClean })
        #expect(model.selection.isEmpty)
        #expect(model.allRows.first { $0.id == "npm" }?.tone == .empty, "the screen scanned again")
        #expect(RemovalLogRow(entry: model.app.logEntries[0]).actionText == "Cleaned tool cache")
    }

    /// The sheet lists what a fresh scan allows, with each note and what stays; a tool that starts before the
    /// confirm is refused by the check right before its entry.
    @Test func theSheetListsNotesAndAToolStartingLaterIsRefused() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let model = makeModel(world)
        await model.refresh()
        for id in ["pip", "pub", "mongodb-binaries", "cursor-state-backup"] { model.setSelected(id, true) }
        world.processes.run("/Users/me/flutter/bin/cache/dart-sdk/bin/dart pub get")
        await model.beginClean()

        let confirmation = try #require(model.confirmation)
        #expect(confirmation.allowed.map(\.id) == ["pip", "mongodb-binaries", "cursor-state-backup"])
        #expect(confirmation.blocked.map(\.leftAloneReason) == ["Quit dart to clean this."])
        let pub = try #require(confirmation.blocked.first)
        #expect(pub.keeps.contains("~/.pub-cache/bin") && pub.note.contains("flutter pub get"))
        #expect(confirmation.allowed.first { $0.id == "mongodb-binaries" }?.note == "Tests download it again, ~300 MB.")
        #expect(confirmation.allowed.first { $0.id == "cursor-state-backup" }?.note.hasPrefix("Cursor's spare copy from ") == true)
        #expect(confirmation.allowed.first { $0.id == "cursor-state-backup" }?.keeps.first?.hasSuffix("/state.vscdb") == true)
        #expect(confirmation.cleanButtonTitle == "Clean 3 items")
        #expect(CachesConfirmation.downloadsLine.contains("fetch or rebuild"))

        world.processes.run("pip3 install requests")
        let report = await model.confirmClean(confirmation)
        let outcomes = Dictionary(uniqueKeysWithValues: report.outcomes.map { ($0.id, $0.status) })
        #expect(outcomes["pip"] == .refused("Quit pip to clean this"))
        #expect(report.cleanedCount == 2)
        #expect(world.exists("Library/Caches/pip/wheels/x.whl"))
        #expect(!world.exists(".cache/mongodb-binaries/mongod-arm64-darwin-7.0.24"))
        #expect(world.exists(".pub-cache/hosted/pub.dev/http-1.0.0/lib/http.dart"))
        model.dismissClean()
        #expect(!model.isShowingCleanSheet && model.cleanReport == nil)
    }

    /// cleanSelected() while another cleanup holds the guard or cleanup.lock is refused with the same messages as
    /// the other cleanups, and nothing is deleted or logged.
    @Test func cleanSelectedWhileAnotherCleanupRunsIsRefused() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let model = makeModel(world)
        await model.refresh()
        model.setSelected("npm", true)

        let lock = try #require(try CleanupLock.tryAcquire(environment: world.environment))
        var report = await model.cleanSelected()
        lock.release()
        #expect(report.outcomes.map(\.status) == [.refused("\(CleanupLock.busyMessage); nothing was deleted")])

        let inner = await model.app.cleaningUp { await model.cleanSelected() }
        report = try #require(inner)
        #expect(report.outcomes.map(\.status) == [.refused("another cleanup is still running; nothing was deleted")])

        #expect(world.exists(".npm/_cacache/index-v5/00/idx"))
        #expect(try RemovalLog(environment: world.environment).entries().isEmpty)
        #expect(model.selection == ["npm"], "a refused clean keeps the selection")
    }
}
