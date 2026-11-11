@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Cleanup queue adapters", .serialized)
@MainActor
struct CleanupQueueAdaptersTests {
    @Test func queuedRemoveAnywayKeepsTheConfirmedLossListAndRestoreUsesTheQueue() async throws {
        let (world, app, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let wip = try world.url("atlas-wip")
        model.selection = model.ids([wip])
        await model.beginRemoveAnyway()
        let confirmation = try #require(model.removeAnywayConfirmation)
        #expect(model.queueRemoveAnyway(confirmation, understood: false) == nil)
        let removed = try #require(model.queueRemoveAnyway(confirmation, understood: true))
        #expect(!model.isShowingRemoveAnywaySheet)
        #expect(await eventually { !app.cleanupQueue.hasPending })
        #expect(removed.cleanedCount == 1)
        #expect(!FileManager.default.fileExists(atPath: wip.path))
        let entry = try #require(app.logEntries.last)
        #expect(entry.action == .worktreeRemoveAnyway && entry.notes == confirmation.lossList.logNotes)
        let restored = try #require(RemovalsModel(app: app).queueRestore(entry.id))
        #expect(await eventually { !app.cleanupQueue.hasPending })
        #expect(restored.cleanedCount == 1)
        #expect(FileManager.default.fileExists(atPath: wip.appending(path: ".git").path))
        #expect(!FileManager.default.fileExists(atPath: wip.appending(path: "scratch.md").path))
    }

    @Test func removeAnywayRefusesANewLossWhileWaiting() async throws {
        let (world, app, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let wip = try world.url("atlas-wip")
        model.selection = model.ids([wip])
        await model.beginRemoveAnyway()
        let confirmation = try #require(model.removeAnywayConfirmation)
        let holder = try await QueueLockHolder.take(app)
        defer { holder.close() }
        let task = try #require(model.queueRemoveAnyway(confirmation, understood: true))
        #expect(await eventually { task.state == .waiting })
        try world.fixture.write("unconfirmed\n", to: "another.txt", in: wip)
        await holder.release()
        #expect(await eventually { !app.cleanupQueue.hasPending })
        #expect(task.cleanedCount == 0 && task.problemCount == 1)
        #expect(task.items[0].result?.detail.contains("changed") == true)
        #expect(FileManager.default.fileExists(atPath: wip.appending(path: "another.txt").path))
        #expect(app.logEntries.isEmpty)
    }

    @Test func queuedPruneRefusesChangedRecords() async throws {
        let (world, app, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let plan = await model.preparePrune()
        let holder = try await QueueLockHolder.take(app)
        defer { holder.close() }
        let task = try #require(model.queuePrune(plan))
        #expect(await eventually { task.state == .waiting })
        try world.fixture.deleteFolder(try world.url("beacon-env"))
        await holder.release()
        #expect(await eventually { !app.cleanupQueue.hasPending })
        #expect(task.cleanedCount == 0 && task.problemCount == 1)
        #expect(task.items[0].result?.detail.contains("changed since they were shown") == true)
        #expect(app.logEntries.isEmpty)
    }

    @Test func queuedCachesRecheckTheirOwnerAndLeaveUnselectedCaches() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let app = AppModel(environment: world.environment)
        let model = CachesModel(app: app, processes: world.processes.source)
        await model.refresh()
        let confirmation = await model.prepareClean(["npm", "pip"])
        let holder = try await QueueLockHolder.take(app)
        defer { holder.close() }
        let task = try #require(model.queueClean(confirmation))
        #expect(await eventually { task.state == .waiting })
        model.setSelected("npm", true)
        #expect(!model.selection.contains("npm"))
        world.processes.run("npm install")
        await holder.release()
        #expect(await eventually { !app.cleanupQueue.hasPending })
        #expect(task.cleanedCount == 1 && task.problemCount == 1)
        #expect(world.exists(".npm/_cacache/index-v5/00/idx"))
        #expect(!world.exists("Library/Caches/pip/wheels/x.whl"))
        #expect(world.exists(CursorStateBackup.backupPath))
        #expect(app.logEntries.map(\.repoPath) == ["pip"])
    }

    @Test func queuedDerivedDataRechecksWorkspaceAndDeletesOnlyConfirmedOrphans() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let orphan = try home.derivedDataEntry("Gone-aaa", workspace: "/Users/nobody/NoProject.xcodeproj")
        let other = try home.derivedDataEntry("Gone-bbb", workspace: "/Users/nobody/OtherProject.xcodeproj")
        let app = AppModel(environment: home.environment().withFakeTools())
        let tools = FakeToolchain()
        let model = DerivedDataModel(app: app, runner: tools.runner)
        await model.refresh()
        let confirmation = await model.prepareDelete(Set(model.rows.map(\.id)))
        let holder = try await QueueLockHolder.take(app)
        defer { holder.close() }
        let task = try #require(model.queueDelete(confirmation))
        #expect(await eventually { task.state == .waiting })
        try home.rewritePlist(of: other, workspace: "/usr/bin")
        await holder.release()
        #expect(await eventually { !app.cleanupQueue.hasPending })
        #expect(task.cleanedCount == 1 && task.problemCount == 1)
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
        #expect(app.logEntries.count == 1)
    }

    @Test func queuedDockerAndSimulatorsUseTheirCommandsInOrder() async throws {
        let world = try DockerSimulatorsWorld()
        defer { world.home.remove() }
        let docker = await world.model.prepareDockerPrune()
        let simulators = await world.model.prepareSimulatorsDelete()
        let first = try #require(world.model.queueDockerPrune(docker))
        let second = try #require(world.model.queueSimulatorsDelete(simulators))
        #expect(world.model.queueDockerPrune(docker) == nil)
        #expect(await eventually { !world.app.cleanupQueue.hasPending })
        #expect(first.cleanedCount == 1 && second.cleanedCount == 1)
        #expect(world.app.logEntries.map(\.action) == [.dockerPrune, .simulatorsDeleteUnavailable])
    }
}
