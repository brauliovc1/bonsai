import Foundation

/// A process that does nothing until the test stops it, its working folder inside a fixture, for the "in use" tests:
/// `/bin/cat` (ps and lsof call it `cat`, `command`) reading a pipe only this process writes to. It never ends on a
/// timer of its own, so a slow machine can't outlast it, and it ends with the test process too. `executable` may be
/// a copy of cat under another name. Safe to start from a `@Sendable` hook and to stop from `defer`.
///
/// Neither `start` nor `stop` calls `Process.waitUntilExit()`: that waits on the current run loop, which a Swift
/// concurrency thread may never run. Both wait for an event, for at most `TestWait.limit`.
public final class SleepingProcess: @unchecked Sendable {
    /// What ps and lsof call the default process.
    public static let command = "cat"

    public struct Failure: Error, CustomStringConvertible {
        public var description: String
    }

    private let executable: URL
    private let condition = NSCondition()
    private var process: Process?
    private var input: FileHandle?
    private var running = false

    public init(executable: URL = URL(fileURLWithPath: "/bin/cat")) {
        self.executable = executable
    }

    /// Starts it in `folder` and returns once it runs: it echoes a byte written before it started, so from then on
    /// ps and lsof see it there. Throws when it can't start or doesn't answer within `TestWait.limit`.
    public func start(in folder: URL) throws {
        let input = Pipe(), output = Pipe()
        // Written before it starts, so nothing is ever written to a pipe whose reader may have ended.
        try input.fileHandleForWriting.write(contentsOf: Data("\n".utf8))
        let sleeper = Process()
        sleeper.executableURL = executable
        sleeper.currentDirectoryURL = folder
        sleeper.standardInput = input
        sleeper.standardOutput = output
        sleeper.standardError = FileHandle.nullDevice
        sleeper.terminationHandler = { [weak self] _ in self?.ended() }
        condition.withLock {
            process = sleeper
            self.input = input.fileHandleForWriting
            running = true
        }
        do {
            try sleeper.run()
        } catch {
            condition.withLock { running = false }
            throw error
        }
        let answer = output.fileHandleForReading
        defer { try? answer.close() }
        guard let answered = Self.readByte(answer) else {
            stop()
            throw Failure(description: "\(executable.lastPathComponent) in \(folder.path) didn't start within \(TestWait.limit)")
        }
        guard answered else {
            throw Failure(description: "\(executable.lastPathComponent) in \(folder.path) ended before it answered")
        }
    }

    public var pid: Int32? {
        condition.withLock { process?.processIdentifier }
    }

    /// Ends it and waits until it has: true once it has ended (also when it was never started), false when it is
    /// still running after `TestWait.limit`.
    @discardableResult
    public func stop() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        try? input?.close()
        input = nil
        if running, let process { kill(process.processIdentifier, SIGKILL) }
        let deadline = Date(timeIntervalSinceNow: TestWait.seconds)
        while running, condition.wait(until: deadline) {}
        return !running
    }

    private func ended() {
        condition.withLock {
            running = false
            condition.broadcast()
        }
    }

    /// One byte from `handle` within `TestWait.limit`: true when it came, false at end of file, nil when none came.
    private static func readByte(_ handle: FileHandle) -> Bool? {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: TestWait.limit)
        while clock.now < end {
            var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let left = clock.now.duration(to: end).components
            let ready = poll(&descriptor, 1, Int32(left.seconds * 1_000 + left.attoseconds / 1_000_000_000_000_000 + 1))
            if ready < 0, errno == EINTR { continue }
            guard ready > 0 else { return ready == 0 ? nil : false }
            var byte: UInt8 = 0
            let count = read(handle.fileDescriptor, &byte, 1)
            if count < 0, errno == EINTR { continue }
            return count == 1
        }
        return nil
    }
}
