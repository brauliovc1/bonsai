import Darwin
import Foundation

public struct DownloadPutBack: Sendable {
    public let home: URL
    public let log: RemovalLog
    public var now: @Sendable () -> Date

    public init(home: URL, log: RemovalLog, now: @escaping @Sendable () -> Date = { Date() }) {
        self.home = home.resolvingSymlinksInPath()
        self.log = log
        self.now = now
    }

    public func unavailableReason(_ entry: RemovalLogEntry) -> String? {
        guard entry.action == .movedToTrash, entry.restoredAt == nil else { return "This item has already been put back." }
        let downloads = home.appending(path: "Downloads")
        let trash = home.appending(path: ".Trash")
        guard DirectoryEntries.kind(ofItemAt: downloads.path) == .directory,
              DirectoryEntries.kind(ofItemAt: trash.path) == .directory,
              URL(fileURLWithPath: entry.path).deletingLastPathComponent().standardizedFileURL == downloads.standardizedFileURL,
              let trashPath = entry.trashPath,
              URL(fileURLWithPath: trashPath).deletingLastPathComponent().standardizedFileURL == trash.standardizedFileURL
        else { return "The original Downloads folder or this item's Trash location is unavailable." }
        guard let identity = entry.trashIdentity,
              DownloadIdentity.read(URL(fileURLWithPath: trashPath)) == identity
        else { return "This file is no longer in the Trash, or it has changed." }
        guard DirectoryEntries.kind(ofItemAt: entry.path) == nil else { return "Another item already uses the original name." }
        return nil
    }

    /// Caller holds cleanup.lock. Exclusive rename also protects against a destination appearing after the check.
    public func putBack(_ entry: RemovalLogEntry) throws -> RemovalLogEntry {
        // Re-read the authoritative entry so a stale UI row cannot restore an item twice.
        guard let stored = try log.entry(id: entry.id), stored == entry else {
            throw DownloadsError("This history entry changed. Refresh and try again.")
        }
        if let reason = unavailableReason(stored) { throw DownloadsError(reason) }
        guard let trashPath = stored.trashPath else { throw DownloadsError("This file's Trash location is unavailable.") }
        let source = URL(fileURLWithPath: trashPath)
        let target = URL(fileURLWithPath: stored.path)
        let sourceFD = open(source.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard sourceFD >= 0 else { throw DownloadsError("Could not open the Trash folder.") }
        defer { close(sourceFD) }
        let targetFD = open(target.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard targetFD >= 0 else { throw DownloadsError("Could not open the original Downloads folder.") }
        defer { close(targetFD) }
        guard DownloadIdentity.read(source) == stored.trashIdentity else { throw DownloadsError("This file changed in the Trash.") }
        guard renameatx_np(sourceFD, source.lastPathComponent, targetFD, target.lastPathComponent, UInt32(RENAME_EXCL)) == 0 else {
            throw DownloadsError("Could not put the file back: \(String(cString: strerror(errno)))")
        }
        let result = RemovalLogEntry(date: now(), mode: .manual, action: .putBack,
            repoPath: target.deletingLastPathComponent().path, path: stored.path,
            estimatedBytes: stored.estimatedBytes, notes: ["Put back from Trash", "Original entry: \(stored.id.uuidString)"])
        // Append immediately after the move, before updating the original row.
        try log.append(result)
        try log.markRestored(id: stored.id, at: now())
        return result
    }
}
