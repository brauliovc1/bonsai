@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// PLAN §4.4: deleting orphaned DerivedData, checked again right before each folder goes.
@Suite("DerivedDataCleaner")
struct DerivedDataCleanerTests {
    @Test func deletesOrphansMeasuresAndLogsOnce() async throws {
        let world = try DerivedDataWorld()
        defer { world.remove() }
        let live = world.project("Live.xcodeproj")
        try FileManager.default.createDirectory(atPath: live, withIntermediateDirectories: true)
        try world.entry("Gone-aaa", workspace: world.project("Gone.xcworkspace"), kibibytes: 8)
        try world.entry("Old-bbb", workspace: world.project("Old.xcodeproj"), kibibytes: 4)
        try world.entry("Live-ccc", workspace: live)
        try world.folder("ModuleCache.noindex")
        let report = await world.scanner().scan()
        #expect(report.orphans.map(\.name) == ["Gone-aaa", "Old-bbb"])

        let deletion = await world.cleaner(freeSpace: [1_000, 13_000]).delete(report.orphans)

        #expect(deletion.deleted.map(\.name) == ["Gone-aaa", "Old-bbb"])
        #expect(deletion.refused.isEmpty && deletion.failed.isEmpty && deletion.logged && deletion.warnings.isEmpty)
        #expect(!world.exists("Gone-aaa") && !world.exists("Old-bbb"))
        #expect(world.exists("Live-ccc") && world.exists("ModuleCache.noindex"))
        #expect(deletion.freedBytes == 12_000)
        // Each folder's du includes its info.plist (one 4 KiB block).
        #expect(report.orphans.map(\.bytes) == [Int64(12 * 1024), Int64(8 * 1024)])

        let entries = try world.log.entries()
        let entry = try #require(entries.first)
        #expect(entries.count == 1 && entry == deletion.entry)
        #expect(entry.action == .derivedDataDelete && entry.mode == .manual && !entry.isRestorable)
        #expect(entry.path == world.root.path)
        #expect(entry.estimatedBytes == Int64(20 * 1024) && entry.freedBytes == 12_000)
        #expect(entry.notes == [
            "deleted Gone-aaa: project \(world.project("Gone.xcworkspace"))",
            "deleted Old-bbb: project \(world.project("Old.xcodeproj"))",
        ])
    }

    @Test func anOrphanWhoseProjectReappearsIsRefused() async throws {
        let world = try DerivedDataWorld()
        defer { world.remove() }
        let workspace = world.project("Back.xcodeproj")
        try world.entry("Back-aaa", workspace: workspace)
        try world.entry("Gone-bbb", workspace: world.project("Gone.xcodeproj"))
        let orphans = await world.scanner().scan().orphans
        try #require(orphans.count == 2)
        try FileManager.default.createDirectory(atPath: workspace, withIntermediateDirectories: true)

        let deletion = await world.cleaner().delete(orphans)

        #expect(deletion.deleted.map(\.name) == ["Gone-bbb"])
        #expect(deletion.refused.map(\.orphan.name) == ["Back-aaa"])
        #expect(deletion.refused.first?.reason == "its project is back at \(workspace)")
        #expect(world.exists("Back-aaa/Build/blob"))
        #expect(try world.log.entries().first?.notes.last == "refused Back-aaa: its project is back at \(workspace)")
    }

    @Test func anOrphanThatChangedSinceTheScanIsRefused() async throws {
        let world = try DerivedDataWorld()
        defer { world.remove() }
        try world.entry("Renamed-aaa", workspace: world.project("A.xcodeproj"))
        try world.entry("Plistless-bbb", workspace: world.project("B.xcodeproj"))
        try world.entry("Linked-ccc", workspace: world.project("C.xcodeproj"))
        let orphans = await world.scanner().scan().orphans
        try #require(orphans.count == 3)
        // Now names another (still missing) project; lost its info.plist; became a symlink to a live folder.
        try world.entry("Renamed-aaa", workspace: world.project("Other.xcodeproj"))
        try FileManager.default.removeItem(at: world.root.appending(path: "Plistless-bbb/info.plist"))
        try FileManager.default.removeItem(at: world.root.appending(path: "Linked-ccc"))
        try FileManager.default.createSymbolicLink(at: world.root.appending(path: "Linked-ccc"), withDestinationURL: world.projects)

        let deletion = await world.cleaner().delete(orphans)

        #expect(deletion.deleted.isEmpty && deletion.entry == nil)
        // Sorted by name: Linked-ccc, Plistless-bbb, Renamed-aaa.
        #expect(deletion.refused.map(\.reason) == [
            "it is no longer a folder",
            "it is now no info.plist",
            "its info.plist now names \(world.project("Other.xcodeproj"))",
        ])
        #expect(world.exists("Renamed-aaa") && world.exists("Plistless-bbb") && world.exists("Linked-ccc"))
        #expect(FileManager.default.fileExists(atPath: world.projects.path))
        #expect(try world.log.entries().isEmpty)
    }

    @Test func xcodeInternalWorkspacesAreNeverOrphans() async throws {
        let world = try DerivedDataWorld()
        defer { world.remove() }
        // The default rules: the fixture's own /var/folders paths are Xcode-internal, even when missing.
        try world.entry("Temp-aaa", workspace: world.project("Gone.xcodeproj"))
        let report = await world.scanner(internalPrefixes: DerivedDataClassifier.xcodeInternalPrefixes).scan()
        #expect(report.entries.map(\.state) == [.xcodeInternal])
        #expect(report.orphans.isEmpty)
        #expect(DerivedDataClassifier().isXcodeInternal("/var/folders/../../Users/x/App.xcodeproj") == false)
        #expect(DerivedDataClassifier().isXcodeInternal("/private/var/folders") == true)
        #expect(DerivedDataClassifier().isXcodeInternal("/var/foldersX/App.xcodeproj") == false)
    }

    @Test func nothingToDeleteLogsNothing() async throws {
        let world = try DerivedDataWorld()
        defer { world.remove() }
        let deletion = await world.cleaner().delete([])
        #expect(deletion.deleted.isEmpty && deletion.entry == nil)
        #expect(try world.log.entries().isEmpty)
    }

    @Test func aLogThatCannotBeWrittenIsAWarning() async throws {
        let world = try DerivedDataWorld()
        defer { world.remove() }
        try world.entry("Gone-aaa", workspace: world.project("Gone.xcodeproj"))
        let orphans = await world.scanner().scan().orphans
        // The settings folder is a file, so the log can't be created.
        try Data("x".utf8).write(to: world.logFolder)

        let deletion = await world.cleaner().delete(orphans)
        #expect(deletion.deleted.count == 1 && !deletion.logged)
        #expect(deletion.warnings.first?.hasPrefix("the DerivedData delete was not logged") == true)
        #expect(deletion.entry != nil)
    }
}
