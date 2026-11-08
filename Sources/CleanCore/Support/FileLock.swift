import Foundation

/// An exclusive `flock` on a file, held until `release()` (or until this object goes away). flock locks belong
/// to the open file, so two handles conflict even inside one process: two app models, two app instances and
/// the app and the CLI all exclude each other. The descriptor is close-on-exec, so git and the other children
/// never inherit the lock.
public final class FileLock: @unchecked Sendable {
    public let url: URL
    private let guardLock = NSLock()
    private var descriptor: Int32

    public struct LockError: Error, Sendable, CustomStringConvertible {
        public var description: String
    }

    private init(url: URL, descriptor: Int32) {
        self.url = url
        self.descriptor = descriptor
    }

    deinit {
        release()
    }

    /// Takes the lock when it is free; nil while another handle holds it. Creates the file (and its folder).
    public static func tryLock(_ url: URL) throws -> FileLock? {
        let descriptor = try open(url)
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return FileLock(url: url, descriptor: descriptor) }
        let failure = errno
        close(descriptor)
        guard failure == EWOULDBLOCK || failure == EINTR else {
            throw LockError(description: "cannot lock \(url.path): \(String(cString: strerror(failure)))")
        }
        return nil
    }

    /// Waits up to `timeout` for the lock, on a clock that doesn't count sleep.
    public static func lock(_ url: URL, timeout: Duration) throws -> FileLock {
        let clock = SuspendingClock()
        let deadline = clock.now.advanced(by: timeout)
        while true {
            if let lock = try tryLock(url) { return lock }
            guard clock.now < deadline else { throw LockError(description: "\(url.path) is locked by another process") }
            usleep(10_000)
        }
    }

    /// Lets go of the lock; later calls do nothing.
    public func release() {
        guardLock.withLock {
            guard descriptor >= 0 else { return }
            flock(descriptor, LOCK_UN)
            close(descriptor)
            descriptor = -1
        }
    }

    private static func open(_ url: URL) throws -> Int32 {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = Darwin.open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else {
            throw LockError(description: "cannot open \(url.path): \(String(cString: strerror(errno)))")
        }
        return descriptor
    }
}
