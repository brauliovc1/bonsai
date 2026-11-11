@testable import CleanAppModel
@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Quick clean categories", .serialized)
@MainActor
struct QuickCleanCategoryTests {
    @Test func allCategoriesUseExistingCleanersAndDownloadsOnlyMoveToTemporaryTrash() async throws {
        let world = try await QuickCleanTestWorld.make(commands: true)
        defer { world.remove() }
        let home = world.app.environment.homeDirectory
        let cache = home.appending(path: ".npm/_cacache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("cache".utf8).write(to: cache.appending(path: "blob"))
        let downloadRoot = home.appending(path: "Downloads")
        try FileManager.default.createDirectory(at: downloadRoot, withIntermediateDirectories: true)
        let download = downloadRoot.appending(path: "old-installer.zip")
        let recent = downloadRoot.appending(path: "recent.zip")
        try Data("old".utf8).write(to: download); try Data("recent".utf8).write(to: recent)
        let derived = try DerivedDataFixture.entry(in: DerivedDataFixture.root(in: home), "QuickOrphan",
            workspace: "/Users/quick-clean-missing-\(UUID().uuidString)/Gone.xcodeproj")
        await world.quick.begin()
        let preview = try #require(world.quick.preview)
        #expect(preview.groups.count == 7 && preview.groups.allSatisfy { !$0.items.isEmpty })
        #expect(world.tools.changingCalls.isEmpty && world.app.cleanupQueue.tasks.isEmpty)
        #expect(preview.moveBytes == 3 && preview.unknownMoveSizeCount == 0)
        let npm = try #require(world.group(.toolCaches).first { $0.id == "cache:npm" })
        let absentTarget = home.appending(path: ".npm/_npx").path
        #expect(npm.paths.contains(absentTarget))
        #expect(world.quick.plan?.operations.contains { $0.work.item.resources.contains(absentTarget) } == true)
        let task = try #require(world.quick.confirm())
        await world.app.cleanupQueue.waitUntilEmpty()
        #expect(world.tools.pruneCalls.count == 1 && world.tools.deleteCalls.count == 1)
        #expect(!world.exists(cache.appending(path: "blob")) && world.exists(cache))
        #expect(!world.exists(derived))
        #expect(!world.exists(download) && world.exists(home.appending(path: ".Trash/old-installer.zip")))
        #expect(world.exists(recent))
        let moved = try #require(task.items.first { $0.resources.contains(CanonicalPath.resolve(download)) })
        #expect(moved.result?.freedBytes == nil && moved.estimatedBytes == nil)
        #expect(try RemovalLog(environment: world.app.environment).entries().filter { $0.action == .movedToTrash }.count == 1)
    }

    @Test func unknownSizesStayUnknownAndMoveBytesDoNotClaimFreedSpace() {
        let preview = QuickCleanPreview(createdAt: Date(), groups: [
            QuickCleanGroup(id: .toolCaches, title: "Caches", detail: "", items: [
                QuickCleanItem(id: "known", title: "Known", detail: "", estimatedBytes: 100),
                QuickCleanItem(id: "unknown", title: "Unknown", detail: "")]),
            QuickCleanGroup(id: .downloads, title: "Downloads", detail: "", items: [
                QuickCleanItem(id: "move", title: "Move", detail: "", estimatedBytes: 50)])])
        #expect(preview.itemCount == 3 && preview.estimatedBytes == 100 && preview.unknownSizeCount == 1)
        #expect(preview.moveBytes == 50 && preview.unknownMoveSizeCount == 0)
    }

    @Test func simulatorScopeChangeRefusesCommand() async throws {
        let world = try await QuickCleanTestWorld.make(commands: true)
        defer { world.remove() }
        await world.quick.begin()
        #expect(world.group(.simulators).count == 2)
        world.tools.unavailable.append(("NEW", "New unavailable", 123))
        let task = try #require(world.quick.confirm())
        await world.app.cleanupQueue.waitUntilEmpty()
        #expect(world.tools.deleteCalls.isEmpty)
        #expect(task.items.first { $0.resources.contains(DockerSimulatorsModel.simulatorsResource) }?.result?.state == .refused)
    }

    @Test func canonicalAliasReservationExcludesTheWholeCacheEntry() async throws {
        let world = try await QuickCleanTestWorld.make()
        defer { world.remove() }
        let home = world.app.environment.homeDirectory
        let cache = home.appending(path: ".npm/_cacache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("cache".utf8).write(to: cache.appending(path: "blob"))
        let alias = home.appending(path: "cache-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: cache)
        let holder = try await QueueLockHolder.take(world.app)
        let blocked = try #require(world.app.cleanupQueue.enqueue(title: "Other", unit: "items", work: [queueWork(alias.path)]))
        await world.quick.begin()
        #expect(world.group(.toolCaches).allSatisfy { $0.id != "cache:npm" })
        #expect(world.quick.preview?.warnings.contains { $0.contains("overlaps") } == true)
        world.app.cleanupQueue.cancel(blocked)
        await holder.release()
        #expect(world.exists(cache.appending(path: "blob")))
    }

    @Test func aCacheOwnerStartingAfterPreviewRefusesTheCapturedCache() async throws {
        let processes = ScriptedProcesses()
        let world = try await QuickCleanTestWorld.make(processes: processes.source)
        defer { world.remove() }
        let cache = world.app.environment.homeDirectory.appending(path: ".npm/_cacache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("cache".utf8).write(to: cache.appending(path: "blob"))
        await world.quick.begin()
        #expect(world.group(.toolCaches).contains { $0.id == "cache:npm" })
        processes.run("npm install")
        let task = try #require(world.quick.confirm())
        await world.app.cleanupQueue.waitUntilEmpty()
        #expect(world.exists(cache.appending(path: "blob")))
        #expect(task.items.first { $0.resources.contains("cache:npm") }?.result?.state == .refused)
    }

}
