import Foundation

/// When Cursor's `state.vscdb.backup` may go (PLAN §4.6): it is 7 or more days old, and `state.vscdb` (the live
/// database with the chats and settings) is a plain file that starts with the SQLite header and is at least half
/// the backup's size. Otherwise the backup may hold chats the live database lost (a reset or truncated database),
/// so it is not offered. `state.vscdb`, `-wal` and `-shm` are never deleted.
public enum CursorStateBackup {
    public static let backupPath = ToolCacheCatalog.globalStorage + "/state.vscdb.backup"
    public static let statePath = ToolCacheCatalog.globalStorage + "/state.vscdb"
    public static let minimumAge: TimeInterval = 7 * 86_400
    /// The first 16 bytes of every SQLite database file.
    public static let sqliteHeader = Array("SQLite format 3\u{0}".utf8)
    /// Why the backup stays when `state.vscdb` doesn't look like a full copy of the chats.
    public static let mayHoldChats = "the backup may hold chats the current database doesn't"

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
            return .refused(mayHoldChats + " (state.vscdb is missing)", date: date)
        }
        guard state.st_mode & S_IFMT == S_IFREG else {
            return .refused(mayHoldChats + " (state.vscdb is not a plain file)", date: date)
        }
        guard hasSQLiteHeader(statePath) else {
            return .refused(mayHoldChats + " (state.vscdb is not an SQLite database)", date: date)
        }
        guard state.st_size * 2 >= info.st_size else {
            let percent = info.st_size > 0 ? Int(state.st_size * 100 / info.st_size) : 0
            return .refused(mayHoldChats + " (state.vscdb is \(percent)% of the backup's size)", date: date)
        }
        return .allowed(date: date)
    }

    /// The file starts with `sqliteHeader` (read without following a symlink).
    static func hasSQLiteHeader(_ path: String) -> Bool {
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var bytes = [UInt8](repeating: 0, count: sqliteHeader.count)
        let count = read(descriptor, &bytes, bytes.count)
        return count == sqliteHeader.count && bytes == sqliteHeader
    }

    /// The confirmation's note: "Cursor's spare copy from 15 May 2026; your current chats stay in `state.vscdb`."
    static func note(date: Date?) -> String {
        let when = date.map { " from " + $0.formatted(.dateTime.day().month(.abbreviated).year()) } ?? ""
        return "Cursor's spare copy\(when); your current chats stay in `state.vscdb`."
    }
}
