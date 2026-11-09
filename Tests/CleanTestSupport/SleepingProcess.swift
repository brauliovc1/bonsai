import Foundation

/// A `/bin/sleep 30` (or `seconds`) whose working folder is inside a fixture, for the "in use" tests. Safe to start from a
/// `@Sendable` hook and to stop from `defer`.
///
/// `stop()` never calls `Process.waitUntilExit()`: that waits on the current run loop, which a Swift
/// concurrency thread may never run. It sends SIGKILL and polls for at most two seconds.
public final class SleepingProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private let seconds: Int

    /// `seconds`: how long it lives unless stopped; longer for a test that runs scans while it is inside.
    public init(seconds: Int = 30) {
        self.seconds = seconds
    }

    /// Starts the process in `folder` and waits briefly so lsof can see it.
    public func start(in folder: URL) throws {
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["\(seconds)"]
        sleeper.currentDirectoryURL = folder
        try sleeper.run()
        lock.withLock { process = sleeper }
        usleep(200_000)
    }

    public var pid: Int32? {
        lock.withLock { process?.processIdentifier }
    }

    public func stop() {
        guard let sleeper = lock.withLock({ process }) else { return }
        if sleeper.isRunning { kill(sleeper.processIdentifier, SIGKILL) }
        for _ in 0..<100 where sleeper.isRunning {
            usleep(20_000)
        }
    }
}
