@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Cleanup queue", .serialized)
@MainActor
struct CleanupQueueTests {
    @Test func tasksRunInOrderAndReportEachItemsMeasuredBytes() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let app = makeApp(fixture)
        let queue = app.cleanupQueue
        let gate = QueueGate()
        defer { gate.open() }
        var order: [String] = []
        let first = try #require(queue.enqueue(title: "one", unit: "folders", work: [
            queueWork("one/a", bytes: 100) { order.append("a"); await gate.wait(); return CleanupItemResult(.cleaned, freedBytes: 40) },
            queueWork("one/b", bytes: 100) { order.append("b"); return CleanupItemResult(.cleaned, freedBytes: 60) }
        ]))
        let second = try #require(queue.enqueue(title: "two", unit: "folders", work: [
            queueWork("two/a") { order.append("c"); return CleanupItemResult(.cleaned, freedBytes: 7) }
        ]))
        #expect(await eventually { gate.entered })
        #expect(first.state == .running && first.items[0].state == .running)
        #expect(second.state == .queued && order == ["a"])
        #expect(app.isCleaningUp)
        #expect(try CleanupLock.tryAcquire(environment: app.environment) == nil)
        #expect(queue.activityText?.contains("1 waiting") == true)
        gate.open()
        #expect(await eventually { !queue.hasPending })
        #expect(order == ["a", "b", "c"])
        #expect(first.completedCount == 2 && first.cleanedCount == 2)
        #expect(first.measuredFreedBytes == Int64(100))
        #expect(second.measuredFreedBytes == Int64(7))
        #expect(!app.isCleaningUp)
        let lock = try #require(try CleanupLock.tryAcquire(environment: app.environment))
        lock.release()
    }

    @Test func cancelQueuedAndStopRunningLeaveTheRemainingItemsUntouched() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let app = makeApp(fixture)
        let queue = app.cleanupQueue
        let gate = QueueGate()
        defer { gate.open() }
        var touched: [String] = []
        let first = try #require(queue.enqueue(title: "one", unit: "items", work: [
            queueWork("a") { await gate.wait(); touched.append("a"); return CleanupItemResult(.cleaned) },
            queueWork("b") { touched.append("b"); return CleanupItemResult(.cleaned) }
        ]))
        let second = try #require(queue.enqueue(title: "two", unit: "items", work: [
            queueWork("c") { touched.append("c"); return CleanupItemResult(.cleaned) }
        ]))
        #expect(await eventually { gate.entered })
        queue.cancel(second)
        queue.cancel(first) // A running task cannot be cancelled in the middle of its item.
        #expect(first.state == .running)
        queue.stop(first)
        gate.open()
        #expect(await eventually { !queue.hasPending })
        #expect(touched == ["a"])
        #expect(second.state == .cancelled)
        #expect(first.state == .stopped && first.items[1].state == .stopped)
        #expect(queue.toasts.first?.needsReview == true)
    }

    @Test func duplicateAndOverlappingPathsAreReservedAcrossActionsAndReleasedOnCancel() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let app = makeApp(fixture)
        let holder = try await QueueLockHolder.take(app)
        defer { holder.close() }
        let queue = app.cleanupQueue
        let root = fixture.scanRoot.path
        let task = try #require(queue.enqueue(title: "deps", unit: "folders", work: [queueWork(root + "/project/node_modules")]))
        #expect(await eventually { task.state == .waiting })
        #expect(queue.enqueue(title: "same", unit: "folders", work: [queueWork(root + "/project/node_modules")]) == nil)
        #expect(queue.enqueue(title: "parent", unit: "worktrees", work: [queueWork(root + "/project")]) == nil)
        #expect(queue.status(for: root + "/project")?.text == "Queued")
        let other = try #require(queue.enqueue(title: "other", unit: "folders", work: [queueWork(root + "/project-other")]))
        queue.cancel(other)
        queue.cancel(task)
        #expect(queue.task(for: root + "/project") == nil)
        await holder.release()
        await queue.waitUntilEmpty()
    }

    @Test func lockHeldByAnotherProcessWaitsThenRunsAndCanBeCancelledWhileWaiting() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let app = makeApp(fixture)
        let queue = app.cleanupQueue
        let holder = try await QueueLockHolder.take(app)
        defer { holder.close() }
        var runs = 0
        let first = try #require(queue.enqueue(title: "cancel", unit: "items", work: [queueWork("first") {
            runs += 1; return CleanupItemResult(.cleaned)
        }]))
        #expect(await eventually { first.state == .waiting })
        #expect(first.waitingReason?.lowercased().contains("another bonsai cleanup") == true)
        queue.cancel(first)
        let second = try #require(queue.enqueue(title: "run", unit: "items", work: [queueWork("second") {
            runs += 1; return CleanupItemResult(.cleaned)
        }]))
        #expect(await eventually { second.state == .waiting })
        #expect(runs == 0)
        await holder.release()
        #expect(await eventually { second.state == .done })
        #expect(runs == 1)
    }

    @Test func successfulToastHidesAndRefusalStaysWithoutOpeningASheet() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let app = makeApp(fixture)
        let queue = app.cleanupQueue
        let timer = QueueGate()
        defer { timer.open() }
        queue.toastSleep = { await timer.wait() }
        let success = try #require(queue.enqueue(title: "success", unit: "folders", work: [queueWork("a") {
            CleanupItemResult(.cleaned, freedBytes: 1024)
        }]))
        #expect(await eventually { timer.entered })
        #expect(queue.toasts.first?.text.contains("Freed") == true)
        #expect(queue.toasts.first?.needsReview == false)
        let refused = try #require(queue.enqueue(title: "refused", unit: "folders", work: [queueWork("b") {
            CleanupItemResult(.refused, detail: "It changed.")
        }]))
        #expect(await eventually { refused.state == .failed })
        #expect(queue.selectedTask == nil)
        timer.open()
        #expect(await eventually { queue.toasts.count == 1 })
        #expect(queue.toasts.first?.task.id == refused.id)
        #expect(queue.toasts.first?.needsReview == true)
        #expect(queue.toasts.first?.text == "0 cleaned, 1 couldn't be")
        #expect(success.state == .done)
    }

    @Test func quitFinishesCurrentItemCancelsTheQueueAndRejectsNewWork() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let app = makeApp(fixture)
        let queue = app.cleanupQueue
        let gate = QueueGate()
        defer { gate.open() }
        let first = try #require(queue.enqueue(title: "one", unit: "items", work: [
            queueWork("a") { await gate.wait(); return CleanupItemResult(.cleaned) }, queueWork("b")
        ]))
        let second = try #require(queue.enqueue(title: "two", unit: "items", work: [queueWork("c")]))
        #expect(await eventually { gate.entered })
        #expect(queue.quitMessage.contains("1 queued tasks won't run"))
        let quitting = Task { await app.prepareToQuit() }
        #expect(await eventually { app.isQuitting })
        #expect(second.state == .cancelled && app.isCleaningUp)
        #expect(queue.enqueue(title: "late", unit: "items", work: [queueWork("late")]) == nil)
        gate.open()
        await quitting.value
        #expect(first.state == .stopped)
        #expect(first.items[0].state == .done && first.items[1].state == .stopped)
        #expect(!app.isCleaningUp && !queue.hasPending)
    }
}
