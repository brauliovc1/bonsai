@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// `cleanup.lock` / `settings.lock` (PLAN §3, wave 5), timeouts on a clock that doesn't count sleep, and a
/// `git worktree remove` that times out.
@Suite("Locks and timeouts")
struct LocksAndTimeoutsTests {
    @Test func fileLocksExcludeEachOtherAndChildrenDontInheritThem() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let url = directory.url.appending(path: "settings/cleanup.lock")

        let first = try #require(try FileLock.tryLock(url), "creates the folder and the file")
        #expect(try FileLock.tryLock(url) == nil, "a second handle, even in this process, is refused")

        // A child started while the lock is held doesn't keep it after this process lets go.
        async let child = ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["1"])
        try await Task.sleep(for: .milliseconds(200))
        first.release()
        let again = try #require(try FileLock.tryLock(url), "free again while the child still runs")
        again.release()
        _ = try await child
    }

    @Test func theCleanupLockLivesInTheSettingsFolder() throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let environment = fixture.environment()
        let held = try #require(try CleanupLock.tryAcquire(environment: environment))
        #expect(CleanupLock.url(environment: environment).path.hasSuffix("clean-claude/cleanup.lock"))
        #expect(try CleanupLock.tryAcquire(environment: environment) == nil)
        held.release()
        #expect(try CleanupLock.tryAcquire(environment: environment) != nil)
        #expect(CleanupLock.busyMessage == "another Bonsai or clean-claude cleanup is running")
    }

    /// A settings read-modify-write waits for `settings.lock`, so it can't put back a value another process
    /// changed in between.
    @Test func settingsUpdatesWaitForTheSettingsLock() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let store = SettingsStore(directory: directory.url)
        try store.save(Settings(autoEnabled: true))

        let held = try #require(try FileLock.tryLock(store.lockURL))
        let done = Flag()
        let update = Task.detached {
            try store.update { $0.lastAutoRun = AutoRunSummary(date: Date(), reportOnly: false) }
            done.set()
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(!done.isSet, "waiting for the lock")
        // What the other process changes while it holds the lock is kept by the waiting update.
        try store.save(Settings(autoEnabled: false))
        held.release()
        try await update.value
        let saved = try store.load()
        #expect(saved.autoEnabled == false && saved.lastAutoRun != nil)
    }

    /// The watchdog sleeps on the clock it is given: on one that never moves, a 50 ms timeout never fires.
    @Test func processTimeoutsRunOnTheirClock() async throws {
        let sleep = URL(fileURLWithPath: "/bin/sleep")
        let stopped = try await ProcessRunner.run(
            executable: sleep, arguments: ["0.5"], timeout: .milliseconds(50), clock: StoppedClock()
        )
        #expect(!stopped.timedOut && stopped.succeeded)
        let running = try await ProcessRunner.run(
            executable: sleep, arguments: ["5"], timeout: .milliseconds(50), clock: ContinuousClock()
        )
        #expect(running.timedOut)
        // Every timeout (git, du, lsof, docker, xcrun) uses this one: it doesn't count time asleep.
        #expect(type(of: ProcessRunner.timeoutClock) == SuspendingClock.self)
    }

    /// git stopped in the middle of `worktree remove`: nothing is logged and it says the folder may be
    /// partly removed.
    @Test func aTimedOutWorktreeRemoveIsInterruptedAndNotLogged() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let path = try await world.sibling("slow")
        let script = world.fixture.url.appending(path: "hanging-git")
        let text = "#!/bin/sh\ncase \" $* \" in *\" worktree remove \"*) exec /bin/sleep 120 ;; esac\n"
            + "exec \"\(world.fixture.git.executable.path)\" \"$@\"\n"
        try Data(text.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        var git = world.fixture.git
        git.executable = script
        // Long enough that the re-check's own git calls never hit it on a loaded machine; only the hanging remove does.
        git.timeout = .seconds(15)
        let environment = world.fixture.environment(clockOffset: 40 * 86_400)
        let worktree = try await world.worktree(path)

        await #expect {
            _ = try await Remover(git: git, settings: Settings(), environment: environment)
                .remove(worktree, mode: .manual, estimatedBytes: nil)
        } throws: { error in
            guard case RemovalError.interrupted = error else { return false }
            return "\(error)" == "interrupted; the folder may be partly removed"
        }
        #expect(!FileManager.default.fileExists(atPath: RemovalLog(environment: environment).fileURL.path))
    }

    @Test func aStopFromTheLastCheckThrowsBeforeGit() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let path = try await world.sibling("idle")
        let environment = world.fixture.environment(clockOffset: 40 * 86_400)
        let worktree = try await world.worktree(path)
        let settings = Settings(autoEnabled: true, autoEnabledAt: Date.distantPast)

        await #expect(throws: RemovalError.self) {
            _ = try await Remover(git: world.fixture.git, settings: settings, environment: environment)
                .remove(worktree, mode: .auto, estimatedBytes: nil, stillAllowed: { .turnedOff })
        }
        #expect(FileManager.default.fileExists(atPath: path.path))
        #expect(!FileManager.default.fileExists(atPath: RemovalLog(environment: environment).fileURL.path))
    }
}

/// A clock that never moves: sleeping on it lasts until the sleeper is cancelled.
private struct StoppedClock: Clock {
    typealias Instant = ContinuousClock.Instant
    let now = ContinuousClock.now
    var minimumResolution: Duration { .zero }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try await Task.sleep(for: .seconds(3_600))
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.withLock { value } }

    func set() {
        lock.withLock { value = true }
    }
}
