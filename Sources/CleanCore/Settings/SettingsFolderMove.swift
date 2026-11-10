import Foundation

/// PLAN §10.2: the settings folder moves from `~/Library/Application Support/clean-claude` to `…/Bonsai` at the
/// first launch of an app or CLI that has this code (`CleanEnvironment.launch`).
///
/// When `clean-claude` is a real folder and nothing is at `Bonsai`: the old folder's `cleanup.lock`, then its
/// `settings.lock` are taken (waited for, never broken, in the order a cleanup takes them), and one
/// `renamex_np(RENAME_SWAP)` swaps the folder with a link `Bonsai -> Bonsai` made just before. In that one step
/// the folder becomes `Bonsai` and `clean-claude` becomes a link to it, so an older binary never finds the old
/// path missing (it would make a new, empty folder there), and through the link it opens the same lock files.
/// Nothing is copied: the log, the settings and the locks keep their inodes.
///
/// What is at each path decides the rest (`decide`, in SettingsFolderMove+Decision): two real folders = both are
/// kept and `Bonsai` is used; anything else at `Bonsai` (a link, a file, another app's `bonsai` folder) = no move,
/// `clean-claude` is used; `clean-claude` a link to a folder elsewhere = no move, the link is used. A notice says
/// where each folder is and which one is used, never to delete anything.
public enum SettingsFolderMove {
    public static let oldName = "clean-claude"
    public static let newName = "Bonsai"
    /// How long the CLI waits, for both locks together, for a cleanup running in another process before it leaves
    /// the move to the next launch.
    public static let lockTimeout: Duration = .seconds(10)
    /// The app's wait for both locks together: it runs at launch on the main thread, before anything shows.
    public static let appLockTimeout: Duration = .milliseconds(1500)

    public enum Outcome: Equatable, Sendable {
        /// No `clean-claude` folder to move: missing, not a folder, or a link to `Bonsai` already.
        case nothingToMove
        case moved
        /// `clean-claude` and `Bonsai` are two real folders: `Bonsai` is used, neither is touched.
        case bothExist
        /// Not moved: a lock wasn't free in time, the file system said no, something else is at `Bonsai`, or
        /// `clean-claude` is a link to a folder elsewhere. `clean-claude` is used for this run.
        case notMoved(String)
    }

    public struct Result: Sendable {
        public var outcome: Outcome
        /// The settings folder for this run.
        public var folder: URL
        /// What to tell the person, once; nil when there is nothing to say.
        public var notice: String?
    }

    /// Moves `<library>/clean-claude` to `<library>/Bonsai` when it should (see above). `lockTimeout` is the
    /// wait for both locks together.
    public static func run(in library: URL, lockTimeout: Duration = lockTimeout) -> Result {
        let paths = Paths(library: library)
        let first = decide(paths)
        guard case .move = first else { return result(of: first, paths) }

        let clock = SuspendingClock()
        let deadline = clock.now.advanced(by: lockTimeout)
        var locks: [FileLock] = []
        defer { locks.reversed().forEach { $0.release() } }
        do {
            // Never creates the folder: if it went away meanwhile, the lock fails and nothing is moved.
            for name in [CleanupLock.fileName, SettingsStore.lockFileName] {
                let left = max(.zero, clock.now.duration(to: deadline))
                locks.append(try FileLock.lock(paths.old.appending(path: name), timeout: left, createsFolder: false))
            }
        } catch {
            return notMoved("\(error)", paths, retries: true)
        }

        // Again under the locks: another launch may have moved it while this one waited.
        let decision = decide(paths)
        guard case .move = decision else { return result(of: decision, paths) }
        let new = paths.new
        if Entry(new).isLeftoverLink, unlink(new.path) != 0 {
            return notMoved("can't remove the link an earlier move left at \(new.path): \(errorText())", paths, retries: true)
        }
        guard symlink(newName, new.path) == 0 else {
            return notMoved("can't make a link at \(new.path): \(errorText())", paths, retries: true)
        }
        guard renamex_np(new.path, paths.old.path, UInt32(RENAME_SWAP)) == 0 else {
            let why = errorText()
            if Entry(new).isLeftoverLink { unlink(new.path) }
            return notMoved("the file system didn't swap the folder and the link: \(why)", paths, retries: true)
        }
        return Result(outcome: .moved, folder: new)
    }

    private static func result(of decision: Decision, _ paths: Paths) -> Result {
        switch decision {
        case .move, .useNew:
            return Result(outcome: .nothingToMove, folder: paths.new)
        case .bothExist:
            let notice = "There are two settings folders: \(paths.new.path) and \(paths.old.path). Bonsai uses "
                + "\(paths.new.path); \(paths.old.path) is left as it is."
            return Result(outcome: .bothExist, folder: paths.new, notice: notice)
        case .keepOld(let why):
            return notMoved(why, paths, retries: false)
        }
    }

    private static func notMoved(_ why: String, _ paths: Paths, retries: Bool) -> Result {
        let notice = retries
            ? "Bonsai couldn't move its settings folder to \(paths.new.path) yet (\(why)). It uses \(paths.old.path) "
                + "this time and tries again next launch."
            : "Bonsai keeps its settings in \(paths.old.path) and doesn't move them to \(paths.new.path): \(why)."
        return Result(outcome: .notMoved(why), folder: paths.old, notice: notice)
    }

    static func errorText() -> String {
        String(cString: strerror(errno))
    }
}
