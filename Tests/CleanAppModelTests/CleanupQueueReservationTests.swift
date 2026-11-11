@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Cleanup queue reservations", .serialized)
@MainActor
struct CleanupQueueReservationTests {
    @Test func duplicateItemsWithinOneSubmissionAreRejected() throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let app = makeApp(fixture)
        #expect(app.cleanupQueue.enqueue(title: "duplicate", unit: "items", work: [queueWork("same"), queueWork("same")]) == nil)
        #expect(!app.cleanupQueue.hasPending)
    }

    @Test func aReplacedSymlinkDoesNotReleaseTheOriginalReservation() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let app = makeApp(fixture)
        let holder = try await QueueLockHolder.take(app)
        defer { holder.close() }
        let first = fixture.url.appending(path: "first")
        let second = fixture.url.appending(path: "second")
        let alias = fixture.url.appending(path: "alias")
        for path in [first, second] { try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true) }
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: first)
        let queue = app.cleanupQueue
        let task = try #require(queue.enqueue(title: "alias", unit: "items", work: [queueWork(alias.path)]))
        #expect(await eventually { task.state == .waiting })
        #expect(queue.task(for: first.path)?.id == task.id)
        try FileManager.default.removeItem(at: alias)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: second)
        #expect(queue.task(for: alias.path)?.id == task.id)
        #expect(queue.task(for: first.path)?.id == task.id)
        #expect(queue.enqueue(title: "same alias", unit: "items", work: [queueWork(alias.path)]) == nil)
        queue.cancel(task)
        await holder.release()
    }

    @Test func aLockIOErrorFailsRatherThanRetryingForever() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        var environment = fixture.environment()
        let file = fixture.url.appending(path: "not-a-folder")
        try Data("file".utf8).write(to: file)
        environment.settingsDirectory = file
        let app = AppModel(environment: environment)
        var ran = false
        let task = try #require(app.cleanupQueue.enqueue(title: "lock error", unit: "items", work: [queueWork("a") {
            ran = true; return CleanupItemResult(.cleaned)
        }]))
        #expect(await eventually { !task.isPending })
        #expect(task.state == .failed && !ran)
        #expect(task.items[0].result?.detail.contains("lock") == true)
        #expect(app.cleanupQueue.toasts.first?.needsReview == true)
    }

    @Test func theInAppGuardIsRespectedWhileOtherRowsStayUsable() async throws {
        let (world, app, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let archive = try world.url("atlas-archive")
        let review = try world.url("atlas-review")
        let confirmation = await model.prepareRemoval(model.ids([archive]))
        var task: CleanupTask?
        await app.cleaningUp {
            task = model.queueRemoval(confirmation)
            #expect(await eventually { task?.state == .waiting })
            #expect(FileManager.default.fileExists(atPath: archive.path))
            model.selection = model.ids([archive])
            #expect(!model.canRemoveSelection)
            model.selection = model.ids([review])
            #expect(model.canRemoveSelection && model.canCleanDependencies)
            #expect(model.queueRemoval(confirmation) == nil)
        }
        #expect(await eventually { !app.cleanupQueue.hasPending })
        #expect(task?.cleanedCount == 1)
        #expect(!FileManager.default.fileExists(atPath: archive.path))
        #expect(FileManager.default.fileExists(atPath: review.path))
    }
}
