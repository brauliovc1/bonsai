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
/// `clean-claude` a folder and something at `Bonsai` too: `Bonsai` is used, neither is touched, and the notice
/// says so. `clean-claude` missing, a link already or not a folder: nothing to do.
public enum SettingsFolderMove {
    public static let oldName = "clean-claude"
    public static let newName = "Bonsai"
    /// How long the move waits for each lock (a cleanup running in another process) before it leaves the move
    /// to the next launch.
    public static let lockTimeout: Duration = .seconds(10)

    public enum Outcome: Equatable, Sendable {
        /// No `clean-claude` folder: missing, a link already, or not a folder.
        case nothingToMove
        case moved
        /// `clean-claude` is a folder and something is at `Bonsai` too: `Bonsai` is used, neither is touched.
        case bothExist
        /// Not moved this time (a lock wasn't free in time, or the file system said no): `clean-claude` is used
        /// for this run and the next launch tries again.
        case notMoved(String)
    }

    public struct Result: Sendable {
        public var outcome: Outcome
        /// The settings folder for this run.
        public var folder: URL
        /// What to tell the person, once; nil when there is nothing to say.
        public var notice: String?
    }

    /// Moves `<library>/clean-claude` to `<library>/Bonsai` when it should (see above).
    public static func run(in library: URL, lockTimeout: Duration = lockTimeout) -> Result {
        let old = library.appending(path: oldName, directoryHint: .isDirectory)
        let new = library.appending(path: newName, directoryHint: .isDirectory)
        guard case .folder = Entry(old) else { return Result(outcome: .nothingToMove, folder: new) }
        guard Entry(new).isFreeForTheMove else { return bothExist(old: old, new: new) }

        let locks: [FileLock]
        do {
            // Never creates the folder: if it went away meanwhile, the lock fails and nothing is moved.
            locks = try [CleanupLock.fileName, SettingsStore.lockFileName].map { name in
                try FileLock.lock(old.appending(path: name), timeout: lockTimeout, createsFolder: false)
            }
        } catch {
            return notMoved("\(error)", old: old, new: new)
        }
        defer { locks.reversed().forEach { $0.release() } }

        // Again under the locks: another launch may have moved it while this one waited.
        guard case .folder = Entry(old) else { return Result(outcome: .nothingToMove, folder: new) }
        let atNew = Entry(new)
        guard atNew.isFreeForTheMove else { return bothExist(old: old, new: new) }
        if atNew.isLeftoverLink, unlink(new.path) != 0 {
            return notMoved("can't remove the link an earlier move left at \(new.path): \(errorText())", old: old, new: new)
        }
        guard symlink(newName, new.path) == 0 else {
            return notMoved("can't make a link at \(new.path): \(errorText())", old: old, new: new)
        }
        guard renamex_np(new.path, old.path, UInt32(RENAME_SWAP)) == 0 else {
            let why = errorText()
            if Entry(new).isLeftoverLink { unlink(new.path) }
            return notMoved("the file system didn't swap the folder and the link: \(why)", old: old, new: new)
        }
        return Result(outcome: .moved, folder: new)
    }

    private static func bothExist(old: URL, new: URL) -> Result {
        let notice = "There are two settings folders, \(new.path) and \(old.path). Bonsai uses \(newName) and "
            + "leaves \(oldName) as it is; delete \(oldName) when you no longer need it."
        return Result(outcome: .bothExist, folder: new, notice: notice)
    }

    private static func notMoved(_ why: String, old: URL, new: URL) -> Result {
        let notice = "Bonsai couldn't move its settings folder to \(new.path) yet (\(why)). It uses \(old.path) "
            + "this time and tries again next launch."
        return Result(outcome: .notMoved(why), folder: old, notice: notice)
    }

    private static func errorText() -> String {
        String(cString: strerror(errno))
    }

    /// What `lstat` finds at a path (links are not followed).
    enum Entry: Equatable {
        case missing
        case folder
        /// A symbolic link and its text.
        case link(String)
        /// A file, or something `lstat` couldn't read.
        case other

        init(_ url: URL) {
            var info = stat()
            guard lstat(url.path, &info) == 0 else {
                self = errno == ENOENT ? .missing : .other
                return
            }
            switch info.st_mode & S_IFMT {
            case S_IFDIR:
                self = .folder
            case S_IFLNK:
                let text = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)
                self = text.map(Entry.link) ?? .other
            default:
                self = .other
            }
        }

        /// The link `Bonsai -> Bonsai` a move makes right before its swap: nothing else makes a link that
        /// points at itself, so one still there was left by a move that stopped in between.
        var isLeftoverLink: Bool { self == .link(SettingsFolderMove.newName) }

        var isFreeForTheMove: Bool { self == .missing || isLeftoverLink }
    }
}
