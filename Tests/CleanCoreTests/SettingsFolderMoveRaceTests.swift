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
            let started = (0..<3).filter { _ in looking.wait(timeout: .now() + 30) == .success }.count
            #expect(started == 3, "round \(round): \(started) of 3 launches started")
            let main = SettingsFolderMove.run(in: library, lockTimeout: .seconds(5)).outcome
            usleep(2_000)
            stop.change { $0 = true }
            #expect(launches.join(timeout: .seconds(30)), "round \(round): a launch never stopped")

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
                    let result = SettingsFolderMove.run(in: library, lockTimeout: .seconds(20))
                    results.change { $0.append(result) }
                }
            }
            for _ in 0..<4 { start.signal() }
            #expect(launches.join(timeout: .seconds(60)), "round \(round): a launch never finished")

            let outcomes = results.value.map(\.outcome)
            #expect(outcomes.filter { $0 == .moved }.count == 1, "round \(round): \(outcomes)")
            #expect(outcomes.filter { $0 == .nothingToMove }.count == 3, "round \(round): \(outcomes)")
            #expect(results.value.allSatisfy { $0.folder == world.new && $0.notice == nil }, "round \(round)")
        }
    }

    /// The wait is for both locks together: with cleanup.lock busy for a while and settings.lock busy longer,
    /// the move gives up when the whole wait is over, not after a second full wait. The app's wait is short.
    @Test func theWaitCoversBothLocksTogether() throws {
        #expect(SettingsFolderMove.appLockTimeout <= .seconds(2), "the app waits on its main thread at launch")
        let world = try SettingsFolderWorld()
        defer { world.remove() }
        try world.makeFolder(world.old, tag: "old")
        let before = try world.snapshot(world.old)
        let cleanup = try LockHolder(world.old.appending(path: "cleanup.lock"), seconds: 2)
        let settings = try LockHolder(world.old.appending(path: "settings.lock"), seconds: 15)
        defer { settings.process.terminate() }

        let started = Date()
        let result = world.move(timeout: .seconds(3))
        let waited = Date().timeIntervalSince(started)

        guard case .notMoved = result.outcome else {
            Issue.record("\(result.outcome)")
            return
        }
        #expect(waited >= 2.5 && waited < 4.5, "waited \(waited) s for a 3 s wait (one wait per lock would be about 5 s)")
        #expect(result.folder == world.old)
        #expect(try world.snapshot(world.old) == before)
        cleanup.wait()
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
