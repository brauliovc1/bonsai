import Foundation

/// Work on threads of its own, never on a shared pool (GCD's global queues or Swift's cooperative pool), so a test
/// doesn't depend on those pools having a free thread soon: in a full test run, other tests can keep them all busy.
public final class TestThreads: Sendable {
    private let group = DispatchGroup()

    public init() {}

    /// Starts `body` on a new thread now.
    public func start(_ body: @escaping @Sendable () -> Void) {
        group.enter()
        let thread = Thread { [group] in
            body()
            group.leave()
        }
        thread.start()
    }

    /// Waits up to `timeout` for every body started so far to return: false when one is still running.
    public func join(timeout: Duration) -> Bool {
        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) * 1e-18
        return group.wait(timeout: .now() + seconds) == .success
    }
}
