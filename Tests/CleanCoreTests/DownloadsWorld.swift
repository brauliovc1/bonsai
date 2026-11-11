@testable import CleanCore
import CleanTestSupport
import Foundation

struct DownloadsWorld: Sendable {
    let directory: TemporaryDirectory
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var home: URL { directory.url }
    var downloads: URL { home.appending(path: "Downloads") }
    var trash: URL { home.appending(path: ".Trash") }
    var log: RemovalLog { RemovalLog(directory: home.appending(path: "settings")) }

    init() throws {
        directory = try TemporaryDirectory(prefix: "bonsai-downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    }

    func file(_ name: String, contents: String = "fixture") throws -> URL {
        let url = downloads.appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func scanner(attached: Set<String> = []) -> DownloadsScanner {
        let now = now
        return DownloadsScanner(home: home, now: { now }, attachedImages: AttachedImages { attached }, addedDate: { url in
            now.addingTimeInterval(url.lastPathComponent.hasPrefix("recent") ? -10 * 86400 : -31 * 86400)
        })
    }

    var trashOperation: TrashOperation {
        let trash = trash
        return TrashOperation { url in
            let target = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        }
    }

    func mover() -> DownloadsMover { DownloadsMover(scanner: scanner(), log: log, trash: trashOperation) }
}
