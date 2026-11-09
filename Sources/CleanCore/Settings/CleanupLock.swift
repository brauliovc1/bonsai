import Foundation

/// `<settingsDir>/cleanup.lock` (PLAN §3): every cleanup that changes anything holds it exclusively for its
/// whole duration: the app's manual cleanups, auto-mode runs and every CLI command run with `--yes`. Across
/// processes, so two app instances or the app and the CLI never clean up at the same time.
public enum CleanupLock {
    public static let fileName = "cleanup.lock"
    /// Why a cleanup was refused while another process (or another app model) holds the lock.
    public static let busyMessage = "another Bonsai cleanup is running"

    public static func url(environment: CleanEnvironment) -> URL {
        environment.settingsDirectory.appending(path: fileName)
    }

    /// The lock, or nil while someone else holds it. Never waits.
    public static func tryAcquire(environment: CleanEnvironment) throws -> FileLock? {
        try FileLock.tryLock(url(environment: environment))
    }
}
