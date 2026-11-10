import Foundation

/// At most `width` processes at a time, for the processes test helpers start themselves: fixture git calls, `bonsai`
/// runs, `make`, `codesign`. Swift Testing starts every test at once, and without a bound hundreds of fixtures
/// start building their repos in the same second, which on a 3-core runner makes every process wait its turn for
/// minutes. The code under test is never limited, here or in production.
///
/// A slot is held from launch to exit, so only processes that end on their own go through it: one that waits for
/// the test (a gate, a lock holder) could hold a slot another helper needs.
public final class ProcessLimit: @unchecked Sendable {
    /// Twice the active cores, at least 4: 22 on an 11-core Mac, 6 on GitHub's 3-core runner.
    public static let helpers = ProcessLimit(width: max(4, 2 * ProcessInfo.processInfo.activeProcessorCount))

    public let width: Int
    private let lock = NSLock()
    private var running = 0
    private var maxRunning = 0
    /// Waiting callers, first come first served.
    private var waiting: [CheckedContinuation<Void, Never>] = []

    public init(width: Int) {
        self.width = max(1, width)
    }

    /// Runs `body` once a slot is free, and frees the slot when `body` returns or throws.
    public func run<T: Sendable>(_ body: () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await body()
    }

    /// The most slots that were taken at once so far.
    public var mostAtOnce: Int {
        lock.withLock { maxRunning }
    }

    private func acquire() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let free = lock.withLock {
                guard running < width else {
                    waiting.append(continuation)
                    return false
                }
                take()
                return true
            }
            if free { continuation.resume() }
        }
    }

    /// Hands the slot to the first waiting caller, or frees it.
    private func release() {
        let next: CheckedContinuation<Void, Never>? = lock.withLock {
            running -= 1
            guard !waiting.isEmpty else { return nil }
            take()
            return waiting.removeFirst()
        }
        next?.resume()
    }

    /// Called holding `lock`.
    private func take() {
        running += 1
        maxRunning = max(maxRunning, running)
    }
}
