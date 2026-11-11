@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Downloads")
struct DownloadsTests {
    @Test func picksOnlyOldTopLevelRegularInstallersAndArchives() async throws {
        let world = try DownloadsWorld()
        defer { world.directory.remove() }
        for name in ["old.dmg", "old.zip", "old.pkg", "recent.zip", "notes.txt", "Fake.app", "child/deep.zip"] {
            _ = try world.file(name)
        }
        try FileManager.default.createDirectory(at: world.downloads.appending(path: "folder.mpkg"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: world.downloads.appending(path: "link.zip"),
                                                  withDestinationURL: world.downloads.appending(path: "old.zip"))
        let report = await world.scanner().scan()
        #expect(report.eligible.map(\.name) == ["old.dmg", "old.pkg", "old.zip"])
        #expect(report.bytes == 21)
        #expect(report.files.allSatisfy { $0.identity.resourceIdentifier.count > 0 })
    }

    @Test func attachedImagesAndFailedMountChecksStay() async throws {
        let world = try DownloadsWorld()
        defer { world.directory.remove() }
        let dmg = try world.file("old.dmg")
        _ = try world.file("old.zip")
        let report = await world.scanner(attached: [dmg.path]).scan()
        #expect(report.eligible.map(\.name) == ["old.zip"])
        #expect(report.files.first(where: { $0.name == "old.dmg" })?.skipReason == "Disk image is attached")
        var scanner = world.scanner()
        scanner.attachedImages = AttachedImages { throw DownloadsError("unavailable") }
        let failed = await scanner.scan()
        #expect(failed.eligible.map(\.name) == ["old.zip"])
        #expect(!failed.warnings.isEmpty)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["images": [["image-path": dmg.path]]], format: .xml, options: 0)
        #expect(try AttachedImages.parse(plist) == [dmg.path])
    }

    @Test func movesIntoFixtureTrashAndLogsBeforeNextMove() async throws {
        let world = try DownloadsWorld()
        defer { world.directory.remove() }
        for name in ["a.zip", "b.pkg"] { _ = try world.file(name) }
        let files = await world.scanner().scan().eligible
        let log = world.log
        let operation = world.trashOperation
        var mover = world.mover()
        mover.trash = TrashOperation { url in
            let expected = url.lastPathComponent == "a.zip" ? 0 : 1
            #expect(try log.entries().count == expected)
            return try operation.move(url)
        }
        let results = await mover.move(files)
        #expect(results.map(\.status) == [.moved, .moved])
        #expect(results.allSatisfy { $0.warnings.isEmpty })
        let entries = try log.entries()
        #expect(entries.map(\.action) == [.movedToTrash, .movedToTrash])
        #expect(entries.map(\.path) == files.map(\.path))
        #expect(entries.allSatisfy { $0.trashPath?.hasPrefix(world.trash.path + "/") == true && $0.trashIdentity != nil })
        #expect(entries.allSatisfy { $0.freedBytes == nil && !$0.isRestorable })
        #expect(!FileManager.default.fileExists(atPath: files[0].path))
        #expect(FileManager.default.fileExists(atPath: world.trash.appending(path: "a.zip").path))
    }

    @Test func replacementsGrowthSymlinksAndNewMountsAreRefused() async throws {
        let world = try DownloadsWorld()
        defer { world.directory.remove() }
        for name in ["replace.zip", "grow.zip", "link.zip", "mount.dmg"] { _ = try world.file(name) }
        let files = await world.scanner().scan().eligible
        let replacement = try world.file("replacement.txt", contents: "fixture")
        try FileManager.default.removeItem(at: world.downloads.appending(path: "replace.zip"))
        try FileManager.default.moveItem(at: replacement, to: world.downloads.appending(path: "replace.zip"))
        _ = try world.file("grow.zip", contents: "larger than before")
        try FileManager.default.removeItem(at: world.downloads.appending(path: "link.zip"))
        try FileManager.default.createSymbolicLink(at: world.downloads.appending(path: "link.zip"),
                                                  withDestinationURL: world.downloads.appending(path: "grow.zip"))
        let mover = DownloadsMover(scanner: world.scanner(attached: [world.downloads.appending(path: "mount.dmg").path]),
                                   log: world.log, trash: world.trashOperation)
        let results = await mover.move(files)
        #expect(results.count == 4)
        #expect(results.allSatisfy { $0.status == .refused })
        #expect(try world.log.entries().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: world.trash.path).isEmpty)
    }

    @Test func putBackRestoresAndNeverOverwrites() async throws {
        let world = try DownloadsWorld()
        defer { world.directory.remove() }
        _ = try world.file("a.zip")
        let files = await world.scanner().scan().eligible
        let moved = await world.mover().move(files)
        let entry = try #require(moved.first?.entry)
        let putBack = DownloadPutBack(home: world.home, log: world.log)
        _ = try world.file("a.zip", contents: "new occupant")
        #expect(putBack.unavailableReason(entry)?.contains("original name") == true)
        #expect(throws: DownloadsError.self) { try putBack.putBack(entry) }
        #expect(try String(contentsOf: world.downloads.appending(path: "a.zip"), encoding: .utf8) == "new occupant")
        try FileManager.default.removeItem(at: world.downloads.appending(path: "a.zip"))
        #expect(putBack.unavailableReason(entry) == nil)
        let restored = try putBack.putBack(entry)
        #expect(restored.action == .putBack)
        #expect(try world.log.entries().count == 2)
        #expect(try world.log.entry(id: entry.id)?.restoredAt != nil)
        #expect(try String(contentsOf: world.downloads.appending(path: "a.zip"), encoding: .utf8) == "fixture")
        #expect(throws: DownloadsError.self) { try putBack.putBack(entry) }
    }

    @Test func replacedTrashFileAndChangedDownloadsRootAreRefused() async throws {
        let world = try DownloadsWorld()
        defer { world.directory.remove() }
        _ = try world.file("a.zip")
        let moved = await world.mover().move(await world.scanner().scan().eligible)
        let entry = try #require(moved.first?.entry)
        try Data("different".utf8).write(to: world.trash.appending(path: "a.zip"))
        let putBack = DownloadPutBack(home: world.home, log: world.log)
        #expect(putBack.unavailableReason(entry) != nil)
        #expect(throws: DownloadsError.self) { try putBack.putBack(entry) }
        let target = world.home.appending(path: "elsewhere")
        try FileManager.default.moveItem(at: world.downloads, to: target)
        try FileManager.default.createSymbolicLink(at: world.downloads, withDestinationURL: target)
        #expect(await world.scanner().scan().eligible.isEmpty)
    }

    @Test func oldHistoryDecodesWithoutTrashFields() throws {
        let entry = RemovalLogEntry(date: Date(), mode: .manual, action: .cacheClean, repoPath: "cache", path: "/fixture")
        let data = try JSONEncoder().encode(entry)
        #expect(try JSONDecoder().decode(RemovalLogEntry.self, from: data) == entry)
        #expect(!String(decoding: data, as: UTF8.self).contains("trashIdentity"))
    }
}
