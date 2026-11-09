@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Tool caches: symlinks and owners")
struct ToolCacheSafetyTests {
    /// A symlink anywhere from the home folder to the target refuses the entry at scan time, and what the link
    /// names survives even when the refused finding is handed to the cleaner.
    @Test(arguments: [".npm", ".npm/_cacache", "Library/Caches", "Library/Application Support/Cursor"])
    func aSymlinkOnTheWayRefusesTheEntry(link: String) async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let outside = try world.replaceWithLink(link)
        defer { try? FileManager.default.removeItem(at: outside) }
        let before = try FileManager.default.subpathsOfDirectory(atPath: outside.path).sorted()

        let report = await world.scanner().scan()
        let affected = report.findings.filter { finding in
            finding.entry.isCleanable && finding.entry.paths.contains { $0 == link || $0.hasPrefix(link + "/") }
        }
        #expect(!affected.isEmpty)
        for finding in affected {
            #expect(finding.verdict == .refused("~/\(link) is a symbolic link"), "\(finding.id): \(finding.verdict)")
            #expect(finding.bytes == nil, "nothing is measured through the link")
        }
        let result = await world.cleaner().clean(report.findings)
        #expect(Set(result.refused.filter { id in affected.contains { $0.id == id.id } }.map(\.id)) == Set(affected.map(\.id)))
        #expect(try FileManager.default.subpathsOfDirectory(atPath: outside.path).sorted() == before)
    }

    /// A target replaced by a link after the scan is refused by the check right before the entry.
    @Test func aLinkThatAppearsAfterTheScanIsRefusedAtCleanTime() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let report = await world.scanner().scan()
        #expect(try report.require("npm").isReady)
        let outside = try world.replaceWithLink(".npm/_npx")
        defer { try? FileManager.default.removeItem(at: outside) }

        let result = await world.cleaner().clean(try report.require(["npm", "pip"]))
        #expect(result.refused.map(\.id) == ["npm"])
        #expect(result.refused.first?.reason == "~/.npm/_npx is a symbolic link")
        #expect(result.cleaned.map(\.id) == ["pip"], "the run goes on with the next entry")
        #expect(FileManager.default.fileExists(atPath: outside.appending(path: "abc123/node_modules/pkg/index.js").path))
        #expect(world.exists(".npm/_cacache/index-v5/00/idx"), "nothing of a refused entry is touched")
    }

    /// The target folder swapped for a link between two children: the entry stops there and what the link
    /// names survives.
    @Test func aTargetSwappedForALinkMidCleanStopsTheEntry() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        try world.home.addFile("Library/Caches/go-build/01/01bb-d", kibibytes: 4)
        let report = await world.scanner().scan()
        let swapped = OutsideBox()
        var cleaner = world.cleaner()
        cleaner.beforeItem = { path in
            guard path.hasSuffix("/go-build/01"), swapped.url == nil else { return }
            swapped.url = try? world.replaceWithLink("Library/Caches/go-build")
        }
        let result = await cleaner.clean(try report.require(["go-build"]))
        let outside = try #require(swapped.url)
        defer { try? FileManager.default.removeItem(at: outside) }
        let cleaned = try #require(result.cleaned.first)
        #expect(cleaned.removedCount == 1, "00 went before the swap")
        #expect(cleaned.failures.count == 1)
        #expect(cleaned.failures.first?.contains("is a symbolic link") == true, "\(cleaned.failures)")
        #expect(FileManager.default.fileExists(atPath: outside.appending(path: "01/01bb-d").path))
        #expect(FileManager.default.fileExists(atPath: outside.appending(path: "trim.txt").path))
        #expect(try world.logEntries().first?.notes.contains { $0.contains("is a symbolic link") } == true)
    }

    /// A symlink child inside a target is removed as a link; its destination survives. A link deeper inside a
    /// child folder isn't followed either.
    @Test func symlinkChildrenGoAsLinks() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let outside = try TemporaryDirectory(prefix: "clean-claude-outside")
        defer { outside.remove() }
        let keep = outside.url.appending(path: "keep.txt")
        try Data("keep".utf8).write(to: keep)
        try FileManager.default.createSymbolicLink(atPath: world.path("Library/Caches/pip/outside"), withDestinationPath: outside.url.path)
        try FileManager.default.createSymbolicLink(atPath: world.path("Library/Caches/pip/http-v2/a/deep"), withDestinationPath: outside.url.path)
        try FileManager.default.createSymbolicLink(atPath: world.path("Library/Caches/pip/file-link"), withDestinationPath: keep.path)

        let report = await world.scanner().scan()
        let result = await world.cleaner().clean(try report.require(["pip"]))
        #expect(result.cleaned.first?.failures == [])
        #expect(world.contents("Library/Caches/pip").isEmpty)
        #expect(FileManager.default.fileExists(atPath: keep.path))
        #expect(try String(contentsOf: keep, encoding: .utf8) == "keep")
    }

    /// A target owned by someone else is refused (checked as if this user had another uid).
    @Test func aFolderOwnedByAnotherUserIsRefused() throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let me = ToolCachePathCheck.userName(getuid())
        #expect(ToolCachePathCheck.check(".npm/_cacache", home: world.url, expect: .directory, uid: getuid() + 1)
            == .refused("~/.npm belongs to \(me), not to you"))
        #expect(ToolCachePathCheck.check(".npm/_cacache", home: world.url, expect: .file) == .refused("~/.npm/_cacache is not a plain file"))
        #expect(ToolCachePathCheck.check(".npm/../etc", home: world.url, expect: .directory) == .refused(".npm/../etc is not a path inside the home folder"))
        #expect(ToolCachePathCheck.check(".npm/nothing/here", home: world.url, expect: .directory) == .missing)
    }

    /// A running owner (canned ps output) refuses the entry; the others stay ready.
    @Test func aRunningOwnerRefusesTheEntry() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        world.processes.run(
            "node /opt/homebrew/lib/node_modules/npm/bin/npm-cli.js install",
            "/usr/bin/java -Xmx2g -cp /x/gradle-launcher-8.5.jar org.gradle.launcher.daemon.bootstrap.GradleDaemon 8.5",
            world.path(".cache/mongodb-binaries/mongod-arm64-darwin-7.0.24") + " --port 56871"
        )
        let report = await world.scanner().scan()
        #expect(try report.require("npm").verdict == .refused("Quit npm to clean this"))
        #expect(try report.require("gradle").verdict == .refused("Quit Gradle to clean this"))
        #expect(try report.require("mongodb-binaries").verdict == .refused("Quit mongod-arm64-darwin-7.0.24 to clean this"))
        #expect(try report.require("npm").runningOwners == ["npm"])
        #expect(try report.require("pip").isReady)
        #expect((try report.require("npm").bytes ?? 0) > 0, "a refused entry still shows its size")
    }

    /// An owner that starts after the scan refuses its entry at clean time; the run goes on with the next.
    @Test func anOwnerThatStartsAfterTheScanRefusesAtCleanTime() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        let report = await world.scanner().scan()
        #expect(try report.require("pip").isReady)
        world.processes.run("/opt/homebrew/opt/python@3.12/bin/python3.12 -m pip install requests")

        let result = await world.cleaner().clean(try report.require(["pip", "npm"]))
        #expect(result.refused.map(\.id) == ["pip"])
        #expect(result.refused.first?.reason == "Quit pip to clean this")
        #expect(result.cleaned.map(\.id) == ["npm"])
        #expect(world.exists("Library/Caches/pip/wheels/x.whl"))
        #expect(try world.logEntries().map(\.repoPath) == ["npm"])
    }

    /// ps that fails means nobody can tell what runs: every cleanable entry is refused.
    @Test func aProcessListThatFailsRefusesEverything() async throws {
        let world = try ToolCacheWorld()
        defer { world.remove() }
        world.processes.fails = true
        let report = await world.scanner().scan()
        #expect(report.ready.isEmpty)
        #expect(try report.require("npm").verdict == .refused("can't tell whether npm or npx is running: ps failed (exit 1): ps: broken"))
        #expect(report.warnings.contains { $0.contains("nothing can be cleaned") })

        world.processes.fails = false
        let ready = try await world.scanner().scan().require(["cocoapods"])
        world.processes.fails = true
        let result = await world.cleaner().clean(ready)
        #expect(result.refused.map(\.id) == ["cocoapods"])
        #expect(world.exists("Library/Caches/CocoaPods/Pods/Release/Alamofire/x"))
    }
}

/// A value set from inside a seam closure.
final class OutsideBox: @unchecked Sendable {
    var url: URL?
}
