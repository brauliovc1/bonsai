@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// The wave-3 review's DerivedData findings (dd1, dd2) with the safe outcome, and the CLI exit status of a
/// cleanup whose log entry could not be written (item 9).
@Suite("DerivedData: wave-3 review")
struct DerivedDataReviewTests {
    // dd1 / item 10: a project on an unplugged drive looks deleted.
    @Test func aProjectOnAnUnmountedVolumeIsNotOrphaned() async throws {
        let world = try DerivedDataWorld()
        defer { world.remove() }
        try world.entry("App-unplugged", workspace: "/Volumes/ReviewUnplugged-\(UUID().uuidString)/App/App.xcodeproj")

        let report = await world.scanner().scan()

        #expect(report.entries.map(\.state) == [.volumeMissing])
        #expect(report.orphans.isEmpty)
    }

    @Test func aMissingProjectOnAMountedVolumeIsOrphaned() async throws {
        let mounted = try #require(try FileManager.default.contentsOfDirectory(atPath: "/Volumes").first)
        let world = try DerivedDataWorld()
        defer { world.remove() }
        try world.entry("App-gone", workspace: "/Volumes/\(mounted)/nonexistent-bonsai-\(UUID().uuidString)/App.xcodeproj")

        let report = await world.scanner().scan()
        #expect(report.entries.map(\.state) == [.orphaned])
    }

    @Test func volumesAreFoundAfterRemovingDots() {
        #expect(DerivedDataClassifier.volume(of: "/Volumes/Drive/App/App.xcodeproj") == "/Volumes/Drive")
        #expect(DerivedDataClassifier.volume(of: "/Volumes/Drive") == "/Volumes/Drive")
        #expect(DerivedDataClassifier.volume(of: "/Users/x/../../Volumes/Drive/a") == "/Volumes/Drive")
        #expect(DerivedDataClassifier.volume(of: "/Volumes") == nil)
        #expect(DerivedDataClassifier.volume(of: "/Users/x/Volumes/Drive") == nil)
    }

    // dd2 / item 11: `/`, the home folder, a folder above it, or a file is never a DerivedData root.
    @Test func theLocatorRefusesRootsThatAreNotDerivedDataFolders() async {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        for value in ["/", "~", "~/Library/..", "/Users"] {
            let location = await DerivedDataLocator(preferences: FakeXcodePreferences(value: value), homeDirectory: home).locate()
            #expect(location.refusal != nil, "\(value) -> \(location.root.path)")
        }
        let custom = await DerivedDataLocator(preferences: FakeXcodePreferences(value: "~/Builds/DD"), homeDirectory: home).locate()
        #expect(custom.refusal == nil)
        let standard = await DerivedDataLocator(preferences: FakeXcodePreferences(value: nil), homeDirectory: home).locate()
        #expect(standard.refusal == nil)
    }

    @Test func theScannerAndCleanerRefuseThoseRootsToo() async throws {
        let world = try DerivedDataWorld()
        defer { world.remove() }
        try world.entry("Gone-aaa", workspace: world.project("Gone.xcodeproj"))
        let file = world.directory.url.appending(path: "a-file")
        try Data("x".utf8).write(to: file)

        for root in [world.home, world.directory.url, URL(fileURLWithPath: "/"), file] {
            var scanner = world.scanner()
            scanner.root = root
            let report = await scanner.scan()
            #expect(report.refusal != nil && report.entries.isEmpty, "\(root.path)")
        }
        let missing = world.directory.url.appending(path: "no-such-DerivedData")
        var scanner = world.scanner()
        scanner.root = missing
        #expect(await scanner.scan().refusal == nil, "a missing root is just empty")

        // The cleaner checks again: told the root is the home folder, it deletes nothing.
        let orphans = await world.scanner().scan().orphans
        try #require(orphans.count == 1)
        var cleaner = world.cleaner()
        cleaner.homeDirectory = world.root
        let deletion = await cleaner.delete(orphans)
        #expect(deletion.deleted.isEmpty && deletion.refused.count == 1)
        #expect(world.exists("Gone-aaa"))
    }

    // Item 9: `docker` and `simulators` exit 1 when the cleanup ran but its log entry wasn't written.
    @Test func aCleanupThatWasNotLoggedExitsOne() {
        let entry = RemovalLogEntry(date: Date(), mode: .manual, action: .dockerPrune, repoPath: "/d", path: "/d")
        #expect(CleanupCommandResult(exitCode: 0, output: "", logEntry: entry).exitStatus == 0)
        #expect(CleanupCommandResult(exitCode: 0, output: "", logEntry: entry, logError: "disk full").exitStatus == 1)
        #expect(CleanupCommandResult(exitCode: 3, output: "", logEntry: entry).exitStatus == 3)
        #expect(CleanupCommandResult(exitCode: 0, output: "", timedOut: true, logEntry: entry).exitStatus == 1)
    }
}
