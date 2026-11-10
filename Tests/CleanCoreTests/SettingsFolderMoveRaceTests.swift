@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// P12c review: launches at the same moment, and how long a launch waits for the locks. Temp folders only.
@Suite("Settings folder move: launches at once")
struct SettingsFolderMoveRaceTests {
    /// Launches that look while another one swaps (each tries without waiting, again and again): one moves, none
    /// ever says there are two folders or that something is in the way; the only other answer is "the lock is
    /// busy" (they don't wait). The launches are threads of their own, all looking before the swap starts.
    @Test func aLaunchLookingDuringAnotherOnesSwapNeverSaysTwoFolders() throws {
        for round in 0..<60 {
            let world = try SettingsFolderWorld()
            defer { world.remove() }
            try world.makeFolder(world.old, tag: "old")
            let library = world.library
            let stop = Shared(false), outcomes = Shared<[SettingsFolderMove.Outcome]>([])
            let looking = DispatchSemaphore(value: 0)
            let launches = TestThreads()
            for _ in 0..<3 {
                launches.start {
                    looking.signal()
                    while !stop.value {
                        let outcome = SettingsFolderMove.run(in: library, lockTimeout: .zero).outcome
                        outcomes.change { $0.append(outcome) }
                    }
                }
            }
            let started = (0..<3).filter { _ in looking.wait(timeout: TestWait.deadline) == .success }.count
            #expect(started == 3, "round \(round): \(started) of 3 launches started within \(TestWait.limit)")
            let main = SettingsFolderMove.run(in: library, lockTimeout: TestWait.limit).outcome
            usleep(2_000)
            stop.change { $0 = true }
            #expect(launches.join(timeout: TestWait.limit), "round \(round): a launch didn't stop within \(TestWait.limit)")

            let all = outcomes.value + [main]
            #expect(all.filter { $0 == .moved }.count == 1, "round \(round)")
            #expect(!all.contains(.bothExist), "round \(round): \(all.filter { $0 == .bothExist }.count) times")
            for case .notMoved(let why) in all {
                #expect(why.contains("is locked by another process"), "round \(round): \(why)")
            }
            #expect(world.entry(world.old) == .link("Bonsai") && world.entry(world.new) == .folder)
        }
    }

    /// Four launches at the same instant, each willing to wait: one moves, the others wait for its locks, look
    /// again under them and use Bonsai.
    @Test func launchesAtTheSameInstantMoveOnce() throws {
        for round in 0..<40 {
            let world = try SettingsFolderWorld()
            defer { world.remove() }
            try world.makeFolder(world.old, tag: "old")
            let library = world.library
            let results = Shared<[SettingsFolderMove.Result]>([])
            let start = DispatchSemaphore(value: 0)
            let launches = TestThreads()
            for _ in 0..<4 {
                launches.start {
                    start.wait()
                    let result = SettingsFolderMove.run(in: library, lockTimeout: TestWait.limit)
                    results.change { $0.append(result) }
                }
            }
            for _ in 0..<4 { start.signal() }
            #expect(launches.join(timeout: TestWait.limit), "round \(round): a launch didn't finish within \(TestWait.limit)")

            let outcomes = results.value.map(\.outcome)
            #expect(outcomes.filter { $0 == .moved }.count == 1, "round \(round): \(outcomes)")
            #expect(outcomes.filter { $0 == .nothingToMove }.count == 3, "round \(round): \(outcomes)")
            #expect(results.value.allSatisfy { $0.folder == world.new && $0.notice == nil }, "round \(round)")
        }
    }

    /// The wait is for both locks together: with cleanup.lock let go halfway through the wait and settings.lock
    /// held throughout, the move gives up when the whole wait is over, not after a second full wait. The app's wait
    /// is short.
    @Test func theWaitCoversBothLocksTogether() throws {
        #expect(SettingsFolderMove.appLockTimeout <= .seconds(2), "the app waits on its main thread at launch")
        let world = try SettingsFolderWorld()
        defer { world.remove() }
        try world.makeFolder(world.old, tag: "old")
        let before = try world.snapshot(world.old)
        let cleanup = try LockHolder(world.old.appending(path: "cleanup.lock"))
        let settings = try LockHolder(world.old.appending(path: "settings.lock"))
        defer {
            cleanup.release()
            settings.release()
        }

        // One wait per lock would give up after about 15 s; the move's own work gets the other 5 s.
        let wait = 10.0, cleanupFreeAfter = 5.0
        let library = world.library
        let result = Shared<SettingsFolderMove.Result?>(nil), waited = Shared<Double?>(nil)
        let starting = DispatchSemaphore(value: 0)
        let mover = TestThreads()
        mover.start {
            starting.signal()
            let started = Date()
            let outcome = SettingsFolderMove.run(in: library, lockTimeout: .seconds(wait))
            waited.change { $0 = Date().timeIntervalSince(started) }
            result.change { $0 = outcome }
        }
        #expect(starting.wait(timeout: TestWait.deadline) == .success, "the move didn't start within \(TestWait.limit)")
        Thread.sleep(forTimeInterval: cleanupFreeAfter)
        #expect(cleanup.release(), "the other process let go of cleanup.lock")
        #expect(mover.join(timeout: TestWait.limit), "the move didn't give up within \(TestWait.limit)")

        let outcome = try #require(result.value)
        guard case .notMoved = outcome.outcome else {
            Issue.record("\(outcome.outcome)")
            return
        }
        let seconds = try #require(waited.value)
        #expect(seconds >= wait - 0.5 && seconds < wait + cleanupFreeAfter,
                "waited \(seconds) s for a \(wait) s wait (one wait per lock would be over \(wait + cleanupFreeAfter) s)")
        #expect(outcome.folder == world.old)
        #expect(try world.snapshot(world.old) == before)
    }
}

/// A value several threads change.
final class Shared<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value { lock.withLock { stored } }

    func change(_ body: (inout Value) -> Void) {
        lock.withLock { body(&stored) }
    }
}
