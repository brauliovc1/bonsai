import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// CI run 42729730759 (3 cores) hung for 58 minutes: ProcessRunner read each child's pipes with blocking reads on
/// GCD's global queues, so with enough calls at once every worker GCD gives those queues was a blocked read, and a
/// child whose reader never got a worker filled its pipe and waited for it forever. Here that pool is full from the
/// start (each worker held by a blocking wait) and many calls with more output than a pipe holds must still finish.
@Suite("ProcessRunner with GCD's global queues full")
struct ProcessRunnerStarvationTests {
    /// Four times what a pipe holds (64 KB), on both pipes.
    private static let bytes = 256 * 1024
    private static let calls = 32
    /// Generous: on a loaded machine these finish in seconds (34 s under `taskpolicy -c background`). The blocking
    /// reads never finished.
    private static let bound = TestWait.limit

    @Test func manyCallsWithLargeOutputFinishWhileTheGlobalQueuesAreFull() async throws {
        let blockers = GlobalQueueBlockers()
        defer { blockers.release() }
        let full = try await blockers.fill()
        #expect(full, "a new job on a global queue still ran, so the pool isn't full (\(blockers.running) workers held)")

        let finished = Shared(0)
        let running = Task {
            await withTaskGroup(of: ProcessResult?.self, returning: [ProcessResult?].self) { group in
                for index in 0..<Self.calls {
                    group.addTask {
                        // Test-only use of sh. Half fill stdout first and half stderr first: either can be the one
                        // nobody reads.
                        let script = index.isMultiple(of: 2)
                            ? #"head -c "$1" /dev/zero; head -c "$1" /dev/zero >&2"#
                            : #"head -c "$1" /dev/zero >&2; head -c "$1" /dev/zero"#
                        let result = try? await ProcessRunner.run(
                            executable: URL(fileURLWithPath: "/bin/sh"),
                            arguments: ["-c", script, "sh", "\(Self.bytes)"],
                            timeout: Self.bound
                        )
                        finished.change { $0 += 1 }
                        return result
                    }
                }
                return await group.reduce(into: []) { $0.append($1) }
            }
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.bound)
        while finished.value < Self.calls, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let inTime = finished.value
        // Lets blocking reads run at last, so a run that fails here ends instead of hanging.
        blockers.release()
        let results = await running.value

        #expect(inTime == Self.calls, "\(inTime) of \(Self.calls) calls finished within \(Self.bound) with the global queues full")
        #expect(results.count == Self.calls)
        for result in results {
            #expect(result?.exitCode == 0 && result?.timedOut == false)
            #expect(result?.stdout.count == Self.bytes)
            #expect(result?.stderr.utf8.count == Self.bytes)
        }
    }
}

/// Holds every worker GCD gives its global queues in a blocking wait, until `release()`.
private final class GlobalQueueBlockers: Sendable {
    /// More jobs on each global queue than GCD gives all of them together (`kern.wq_max_constrained_threads`, 64),
    /// so every queue keeps jobs waiting.
    private static let perQueue = 80
    private let gate = DispatchGroup()
    private let started = Shared(0)
    private let released = Shared(false)

    init() {
        gate.enter()
        for qos in [DispatchQoS.QoSClass.userInteractive, .userInitiated, .default, .utility, .background] {
            for _ in 0..<Self.perQueue {
                DispatchQueue.global(qos: qos).async { [gate, started] in
                    started.change { $0 += 1 }
                    gate.wait()
                }
            }
        }
    }

    /// Workers held right now.
    var running: Int { started.value }

    /// Waits until GCD stops adding workers, then gives a new job on the utility queue (the one ProcessRunner's
    /// reads used) a second: true when it didn't run, so the pool is full. A job that ran found a worker GCD was
    /// still adding (a slow machine adds them slowly), so it looks again, for at most `TestWait.limit`.
    func fill() async throws -> Bool {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: TestWait.limit)
        repeat {
            var last = -1, steady = 0
            while steady < 5, clock.now < end {
                try await Task.sleep(for: .milliseconds(100))
                let now = running
                steady = now == last ? steady + 1 : 0
                last = now
            }
            let probe = Shared(false)
            DispatchQueue.global(qos: .utility).async { probe.change { $0 = true } }
            try await Task.sleep(for: .seconds(1))
            if !probe.value { return true }
        } while clock.now < end
        return false
    }

    /// Lets every held worker go; later calls do nothing.
    func release() {
        var first = false
        released.change { isReleased in
            first = !isReleased
            isReleased = true
        }
        if first { gate.leave() }
    }
}
