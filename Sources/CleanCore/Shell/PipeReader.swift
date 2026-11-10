import Foundation

/// Reads one pipe to its end on a thread of its own, started as soon as the reader is made.
///
/// The read blocks until the child closes its end, so it must never hold a thread of a shared pool (GCD's global
/// queues or Swift's cooperative pool): with enough reads at once there the pool is full of them, a child whose
/// reader never gets a thread fills its pipe and waits forever, and nothing else on that pool runs (CI run
/// 42729730759 hung for 58 minutes that way).
final class PipeReader: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Data?
    private var waiter: CheckedContinuation<Data, Never>?

    init(_ handle: FileHandle, name: String) {
        let thread = Thread { [self] in
            let data = (try? handle.readToEnd()) ?? Data()
            try? handle.close()
            finish(data)
        }
        thread.name = name
        thread.start()
    }

    /// Everything the pipe held, once its writer closed it. One caller awaits it.
    func data() async -> Data {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock {
                if result == nil { waiter = continuation }
                return result
            }
            if let ready { continuation.resume(returning: ready) }
        }
    }

    private func finish(_ data: Data) {
        let waiting = lock.withLock {
            result = data
            defer { waiter = nil }
            return waiter
        }
        waiting?.resume(returning: data)
    }
}
