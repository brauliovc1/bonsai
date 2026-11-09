import Foundation

/// When Cursor's `state.vscdb.backup` may go (PLAN §4.6): it is 7 or more days old, and `state.vscdb` (the live
/// database with the chats and settings) exists as a plain file larger than 0 bytes. Otherwise the backup may be
/// the only good copy, so it is not offered. `state.vscdb`, `-wal` and `-shm` are never deleted.
public enum CursorStateBackup {
    public static let backupPath = ToolCacheCatalog.globalStorage + "/state.vscdb.backup"
    public static let statePath = ToolCacheCatalog.globalStorage + "/state.vscdb"
    public static let minimumAge: TimeInterval = 7 * 86_400

    enum Decision: Sendable, Hashable {
        /// It may go; `date` is its modification date.
        case allowed(date: Date)
        case refused(String, date: Date?)
    }

    /// The backup must already have passed the path check (a plain file, no symlink on the way).
    static func decide(home: URL, now: Date) -> Decision {
        let backup = home.appending(path: backupPath).path
        var info = stat()
        guard lstat(backup, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            return .refused("the backup is no longer a plain file", date: nil)
        }
        let date = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
        let age = now.timeIntervalSince(date)
        guard age >= minimumAge else {
            let days = max(0, Int(age / 86_400))
            return .refused("it's only \(days) \(days == 1 ? "day" : "days") old; Cursor may still need it", date: date)
        }
        var state = stat()
        let statePath = home.appending(path: Self.statePath).path
        guard lstat(statePath, &state) == 0 else {
            return .refused("state.vscdb is missing, so this backup may be the only copy of your chats", date: date)
        }
        guard state.st_mode & S_IFMT == S_IFREG else {
            return .refused("state.vscdb is not a plain file, so this backup may be the only copy of your chats", date: date)
        }
        guard state.st_size > 0 else {
            return .refused("state.vscdb is empty, so this backup may be the only copy of your chats", date: date)
        }
        return .allowed(date: date)
    }

    /// The confirmation's note: "Cursor's spare copy from 15 May 2026; your current chats stay in `state.vscdb`."
    static func note(date: Date?) -> String {
        let when = date.map { " from " + $0.formatted(.dateTime.day().month(.abbreviated).year()) } ?? ""
        return "Cursor's spare copy\(when); your current chats stay in `state.vscdb`."
    }
}
