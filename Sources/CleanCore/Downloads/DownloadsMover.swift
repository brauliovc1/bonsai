import Foundation

/// Tests supply an operation that moves only within their temporary home.
public struct TrashOperation: Sendable {
    public var move: @Sendable (URL) throws -> URL
    public init(_ move: @escaping @Sendable (URL) throws -> URL) { self.move = move }
    public static let live = Self { url in
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        guard let result else { throw DownloadsError("The system did not return the file's location in Trash.") }
        return result as URL
    }
}

public struct DownloadMoveResult: Sendable {
    public enum Status: String, Sendable { case moved, refused, failed }
    public let file: DownloadFile
    public let status: Status
    public let reason: String
    public let entry: RemovalLogEntry?
    public let warnings: [String]
}

/// Called under the app queue or CLI's cleanup.lock, like the other manual cleaners.
public struct DownloadsMover: Sendable {
    public var scanner: DownloadsScanner
    public var log: RemovalLog
    public var trash: TrashOperation

    public init(scanner: DownloadsScanner, log: RemovalLog, trash: TrashOperation = .live) {
        self.scanner = scanner
        self.log = log
        self.trash = trash
    }

    public func move(_ files: [DownloadFile]) async -> [DownloadMoveResult] {
        var results: [DownloadMoveResult] = []
        for file in files {
            if Task.isCancelled { break }
            results.append(await move(file))
        }
        return results
    }

    public func move(_ file: DownloadFile) async -> DownloadMoveResult {
        let fresh = await scanner.scan()
        guard let current = fresh.files.first(where: { $0.path == file.path }),
              file.canMove, current.canMove, current.identity == file.identity,
              current.addedAt == file.addedAt,
              DownloadIdentity.read(URL(fileURLWithPath: file.path)) == file.identity
        else {
            return DownloadMoveResult(file: file, status: .refused,
                reason: fresh.files.first(where: { $0.path == file.path })?.skipReason ?? "The file changed or is no longer an old download. Refresh and try again.",
                entry: nil, warnings: [])
        }
        do {
            let destination = try trash.move(URL(fileURLWithPath: file.path))
            let identity = DownloadIdentity.read(destination)
            let entry = RemovalLogEntry(date: scanner.now(), mode: .manual, action: .movedToTrash,
                repoPath: scanner.directory.path, path: file.path, estimatedBytes: file.bytes,
                notes: ["Moved to Trash. This does not free space until the Trash is emptied."],
                trashPath: destination.path, trashIdentity: identity)
            var warnings: [String] = []
            do { try log.append(entry) }
            catch { warnings.append("Moved to Trash, but could not write its history: \(error.localizedDescription)") }
            return DownloadMoveResult(file: file, status: .moved, reason: "Moved to Trash", entry: entry, warnings: warnings)
        } catch {
            return DownloadMoveResult(file: file, status: .failed, reason: error.localizedDescription, entry: nil, warnings: [])
        }
    }
}
