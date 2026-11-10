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

    private func sizes(_ cache: FolderSizeCache, _ folder: URL, du: URL, log: [RemovalLogEntry] = []) async -> Int64? {
        let checkout = folder.deletingLastPathComponent().path
        return await cache.sizes(of: [FolderSizeCache.Folder(url: folder, checkout: checkout)], du: du, log: log)[folder.path]
    }

    @Test func aFolderIsMeasuredAgainWhenItOrAFirstLevelEntryChanges() async throws {
        let temp = try TemporaryDirectory(prefix: "bonsai-sizes")
        defer { temp.remove() }
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let du = try #require(fixture.environment().tools.du)
        let cache = FolderSizeCache(environment: fixture.environment())
        let folder = temp.url.appending(path: "node_modules", directoryHint: .isDirectory)
        try file("pkg/deep/a.bin", in: folder, kibibytes: 64)

        let measured = try #require(await sizes(cache, folder, du: du))
        #expect(measured >= 64 * 1024)
        #expect(FileManager.default.fileExists(atPath: cache.fileURL.path), "sizes.json in the settings folder")

        // Two levels down: neither the folder's nor its first-level entries' mtimes move, so the cache is used.
        try file("pkg/deep/b.bin", in: folder, kibibytes: 512)
        #expect(await sizes(cache, folder, du: du) == measured)

        // A new file in a first-level folder (pkg) moves pkg's mtime: measured again.
        try file("pkg/c.bin", in: folder, kibibytes: 256)
        let again = try #require(await sizes(cache, folder, du: du))
        #expect(again >= measured + 768 * 1024)

        // A new entry at the top changes the folder's own mtime: measured again.
        try file("d.bin", in: folder, kibibytes: 128)
        #expect(try #require(await sizes(cache, folder, du: du)) >= again + 128 * 1024)
    }

    @Test func entriesLastAnHourAndABrokenFileIsAnEmptyCache() async throws {
        #expect(FolderSizeCache.maxAge == 3_600)
        let temp = try TemporaryDirectory(prefix: "bonsai-sizes")
        defer { temp.remove() }
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let du = try #require(fixture.environment().tools.du)
        var cache = FolderSizeCache(environment: fixture.environment())
        let folder = temp.url.appending(path: ".next", directoryHint: .isDirectory)
        try file("cache/deep/a.bin", in: folder, kibibytes: 16)
        let measured = try #require(await sizes(cache, folder, du: du))
        try file("cache/deep/b.bin", in: folder, kibibytes: 256)
        #expect(await sizes(cache, folder, du: du) == measured)

        cache.now = { Date().addingTimeInterval(FolderSizeCache.maxAge + 60) }
        let later = try #require(await sizes(cache, folder, du: du))
        #expect(later >= measured + 256 * 1024, "an hour later it is measured again")

        try Data("not json".utf8).write(to: cache.fileURL)
        cache.now = { Date() }
        #expect(await sizes(cache, folder, du: du) == later)
        #expect(cache.load()[folder.path]?.bytes == later, "the broken file was replaced")

        // A folder that is gone is left out.
        #expect(await sizes(cache, temp.url.appending(path: "gone", directoryHint: .isDirectory), du: du) == nil)
    }

    @Test func aCleanupLoggedForTheCheckoutAfterTheMeasurementMakesItStale() async throws {
        let temp = try TemporaryDirectory(prefix: "bonsai-sizes")
        defer { temp.remove() }
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let du = try #require(fixture.environment().tools.du)
        let cache = FolderSizeCache(environment: fixture.environment())
        let shop = temp.url.appending(path: "shop", directoryHint: .isDirectory)
        let other = temp.url.appending(path: "other", directoryHint: .isDirectory)
        let modules = shop.appending(path: "node_modules", directoryHint: .isDirectory)
        try file("pkg/deep/a.bin", in: modules, kibibytes: 32)
        let measured = try #require(await sizes(cache, modules, du: du))
        try file("pkg/deep/b.bin", in: modules, kibibytes: 512)

        func entry(_ path: URL, _ action: RemovalAction, secondsFromNow: TimeInterval) -> RemovalLogEntry {
            RemovalLogEntry(
                date: Date().addingTimeInterval(secondsFromNow), mode: .manual, action: action, repoPath: path.path,
                path: path.path, branch: nil, headSha: nil, kind: .main, estimatedBytes: nil, freedBytes: nil, notes: []
            )
        }
        // Older than the measurement, or about another checkout: still cached.
        #expect(await sizes(cache, modules, du: du, log: [entry(shop.appending(path: ".next"), .lightClean, secondsFromNow: -600)]) == measured)
        #expect(await sizes(cache, modules, du: du, log: [entry(other.appending(path: "dist"), .lightClean, secondsFromNow: 5)]) == measured)
        // A light clean of another folder of the same checkout (the Worktrees screen or the CLI): measured again.
        let afterClean = try #require(await sizes(cache, modules, du: du, log: [entry(shop.appending(path: ".next"), .lightClean, secondsFromNow: 5)]))
        #expect(afterClean >= measured + 512 * 1024)
        // The checkout removed (and made again): measured again.
        try file("pkg/deep/c.bin", in: modules, kibibytes: 256)
        let afterRemove = try #require(await sizes(cache, modules, du: du, log: [entry(shop, .worktreeRemove, secondsFromNow: 5)]))
        #expect(afterRemove >= afterClean + 256 * 1024)
    }
}
