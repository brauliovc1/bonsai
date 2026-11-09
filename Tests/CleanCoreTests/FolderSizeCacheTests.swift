@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Folder size cache")
struct FolderSizeCacheTests {
    private func file(_ relative: String, in folder: URL, kibibytes: Int) throws {
        let url = folder.appending(path: relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: kibibytes * 1024).write(to: url)
    }

    @Test func anUnchangedFolderIsNotMeasuredAgainAndAChangedOneIs() async throws {
        let temp = try TemporaryDirectory(prefix: "clean-claude-sizes")
        defer { temp.remove() }
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let du = try #require(fixture.environment().tools.du)
        let cache = FolderSizeCache(environment: fixture.environment())
        let folder = temp.url.appending(path: "node_modules", directoryHint: .isDirectory)
        try file("pkg/a.bin", in: folder, kibibytes: 64)

        let first = await cache.sizes(of: [folder], du: du)
        let measured = try #require(first[folder.path])
        #expect(measured >= 64 * 1024)
        #expect(FileManager.default.fileExists(atPath: cache.fileURL.path), "sizes.json in the settings folder")

        // Deep inside: the folder's own mtime doesn't move, so the cached size is used.
        try file("pkg/b.bin", in: folder, kibibytes: 512)
        #expect(await cache.sizes(of: [folder], du: du)[folder.path] == measured)

        // A new entry at the top changes the folder's mtime: measured again.
        try file("c.bin", in: folder, kibibytes: 4)
        let again = try #require(await cache.sizes(of: [folder], du: du)[folder.path])
        #expect(again >= measured + 512 * 1024)
    }

    @Test func oldEntriesAreMeasuredAgainAndABrokenFileIsAnEmptyCache() async throws {
        let temp = try TemporaryDirectory(prefix: "clean-claude-sizes")
        defer { temp.remove() }
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let du = try #require(fixture.environment().tools.du)
        var cache = FolderSizeCache(environment: fixture.environment())
        let folder = temp.url.appending(path: ".next", directoryHint: .isDirectory)
        try file("cache/a.bin", in: folder, kibibytes: 16)
        let measured = try #require(await cache.sizes(of: [folder], du: du)[folder.path])
        try file("cache/b.bin", in: folder, kibibytes: 256)

        cache.now = { Date().addingTimeInterval(FolderSizeCache.maxAge + 60) }
        let later = try #require(await cache.sizes(of: [folder], du: du)[folder.path])
        #expect(later >= measured + 256 * 1024, "a day later it is measured again")

        try Data("not json".utf8).write(to: cache.fileURL)
        cache.now = { Date() }
        #expect(await cache.sizes(of: [folder], du: du)[folder.path] == later)
        #expect(cache.load()[folder.path]?.bytes == later, "the broken file was replaced")

        // A folder that is gone is left out.
        let gone = temp.url.appending(path: "gone", directoryHint: .isDirectory)
        #expect(await cache.sizes(of: [gone], du: du).isEmpty)
    }

    @Test func aFolderReplacedAtTheSamePathIsMeasuredAgain() async throws {
        let temp = try TemporaryDirectory(prefix: "clean-claude-sizes")
        defer { temp.remove() }
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let du = try #require(fixture.environment().tools.du)
        let cache = FolderSizeCache(environment: fixture.environment())
        let folder = temp.url.appending(path: "build", directoryHint: .isDirectory)
        try file("a.bin", in: folder, kibibytes: 8)
        let measured = try #require(await cache.sizes(of: [folder], du: du)[folder.path])
        let entry = try #require(cache.load()[folder.path])

        // Another folder at the same path with the same mtime: a different inode.
        try FileManager.default.removeItem(at: folder)
        try file("big.bin", in: folder, kibibytes: 300)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: entry.modified)], ofItemAtPath: folder.path)
        let again = try #require(await cache.sizes(of: [folder], du: du)[folder.path])
        #expect(again > measured)
    }
}
