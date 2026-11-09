@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("DerivedData model")
@MainActor
struct DerivedDataModelTests {
    /// A fake home with a DerivedData root, an app model on it, and the scripted toolchain.
    private struct World {
        let home: FakeHome
        let toolchain: FakeToolchain
        let app: AppModel
        let model: DerivedDataModel
    }

    private func makeWorld() throws -> World {
        let home = try FakeHome()
        let toolchain = FakeToolchain()
        let app = AppModel(environment: home.environment().withFakeTools())
        return World(home: home, toolchain: toolchain, app: app, model: DerivedDataModel(app: app, runner: toolchain.runner))
    }

    @Test func everyStateIsShownAndOnlyOrphansAreSelectable() async throws {
        let world = try makeWorld()
        defer { world.home.remove() }
        try world.home.derivedDataEntry("Gone-aaa", workspace: goneWorkspace("Gone"), kibibytes: 40)
        try world.home.derivedDataEntry("Live-bbb", workspace: "/usr/bin")
        try world.home.derivedDataEntry("ModuleCache.noindex", workspace: nil)
        try world.home.derivedDataEntry("Drive-ccc", workspace: "/Volumes/NoSuchDrive-bonsai/App.xcodeproj")
        try world.home.derivedDataEntry("Temp-ddd", workspace: "/var/folders/zz/abc/T/Scratch.xcodeproj")
        let broken = try world.home.derivedDataEntry("Broken-eee", workspace: nil)
        try Data("not a plist".utf8).write(to: broken.appending(path: "info.plist"))

        await world.model.refresh()

        let rows = Dictionary(uniqueKeysWithValues: world.model.allRows.map { ($0.name, $0) })
        #expect(rows.count == 6)
        #expect(rows["Gone-aaa"]?.state == .orphaned)
        #expect(rows["Live-bbb"]?.state == .live)
        #expect(rows["ModuleCache.noindex"]?.state == .noInfoPlist)
        #expect(rows["Drive-ccc"]?.state == .volumeMissing)
        #expect(rows["Temp-ddd"]?.state == .xcodeInternal)
        #expect(rows["Broken-eee"]?.state == .unreadable)

        // Only the orphan is selectable; every other row is read-only with a one-line reason.
        #expect(world.model.allRows.filter(\.isSelectable).map(\.name) == ["Gone-aaa"])
        for row in world.model.allRows where !row.isSelectable {
            #expect(row.reason.hasSuffix("Read-only."), "\(row.name): \(row.reason)")
            #expect(row.shortReason.hasSuffix("Read-only."), "\(row.name): \(row.shortReason)")
            #expect(!row.reason.contains("\n") && !row.shortReason.contains("\n"))
        }
        #expect(rows["Drive-ccc"]?.reason.contains("drive that isn't connected") == true)
        #expect(rows["Drive-ccc"]?.shortReason == "On a drive that isn't connected. Read-only.")
        #expect(rows["Gone-aaa"]?.reason.contains(goneWorkspace("Gone")) == true)
        #expect(rows["Gone-aaa"]?.sizeText != "–")
        #expect(world.model.orphanBytes == rows["Gone-aaa"]?.bytes)

        // Wave 4: the arrow keys move the selection onto any row, read-only ones too; only orphans count.
        world.model.selection = Set(world.model.allRows.map(\.id))
        #expect(world.model.selection.count == world.model.allRows.count, "keyboard focus is not taken away")
        #expect(world.model.selectedOrphans.map(\.name) == ["Gone-aaa"])
        #expect(world.model.canDelete)
        world.model.selection = [rows["Live-bbb"]!.id]
        #expect(world.model.selection == [rows["Live-bbb"]!.id], "moving onto a read-only row keeps the selection")
        #expect(world.model.selectedOrphans.isEmpty)
        #expect(!world.model.canDelete, "but nothing orphaned is selected")
        world.model.selection = [rows["Live-bbb"]!.id, rows["Gone-aaa"]!.id]
        #expect(world.model.canDelete)
    }

    /// Wave 4: the arrow keys walk the table: orphan, read-only row, orphan again. The selection follows
    /// them, and "Delete orphaned…" is about the orphans only, from a fresh scan.
    @Test func walkingTheSelectionOverReadOnlyRowsStillDeletesOnlyFreshOrphans() async throws {
        let world = try makeWorld()
        defer { world.home.remove() }
        let orphan = try world.home.derivedDataEntry("Gone-aaa", workspace: goneWorkspace("Gone"))
        let live = try world.home.derivedDataEntry("Live-bbb", workspace: "/usr/bin")
        let other = try world.home.derivedDataEntry("Gone-ccc", workspace: goneWorkspace("Other"))
        await world.model.refresh()
        let ids = Dictionary(uniqueKeysWithValues: world.model.allRows.map { ($0.name, $0.id) })

        for step in [["Gone-aaa"], ["Live-bbb"], ["Gone-ccc"]] {
            world.model.selection = Set(step.compactMap { ids[$0] })
            #expect(world.model.selection.count == 1, "\(step)")
        }
        world.model.selection = Set(ids.values)
        await world.model.beginDelete()
        let confirmation = try #require(world.model.confirmation)

        #expect(confirmation.items.map(\.name).sorted() == ["Gone-aaa", "Gone-ccc"], "the read-only row is not in the sheet")
        // One orphan's project comes back before the confirm: the fresh scan refuses it.
        try world.home.rewritePlist(of: other, workspace: "/usr/bin")
        let report = await world.model.confirmDelete(confirmation)
        #expect(report.deletedCount == 1)
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
        #expect(FileManager.default.fileExists(atPath: live.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    @Test func deleteGivesTheCleanerOnlyTheOrphans() async throws {
        let world = try makeWorld()
        defer { world.home.remove() }
        let orphan = try world.home.derivedDataEntry("Gone-aaa", workspace: goneWorkspace("Gone"), kibibytes: 40)
        let live = try world.home.derivedDataEntry("Live-bbb", workspace: "/usr/bin")
        let cache = try world.home.derivedDataEntry("ModuleCache.noindex", workspace: nil)
        await world.model.refresh()

        // Even asked for every folder (the selection would never hold them), only the orphan is listed.
        let confirmation = await world.model.prepareDelete(Set(world.model.allRows.map(\.id)))
        #expect(confirmation.allowed.map(\.name) == ["Gone-aaa"])
        #expect(confirmation.blocked.map(\.name).sorted() == ["Live-bbb", "ModuleCache.noindex"])
        #expect(confirmation.blocked.allSatisfy { $0.orphan == nil && $0.leftAloneReason != nil })
        #expect(confirmation.deleteButtonTitle == "Delete 1 folder")

        let report = await world.model.confirmDelete(confirmation)
        #expect(report.deletedCount == 1)
        #expect(report.outcomes.map(\.item.name) == ["Gone-aaa"])
        #expect(report.summary.hasPrefix("Deleted 1 folder"))
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
        #expect(FileManager.default.fileExists(atPath: live.path))
        #expect(FileManager.default.fileExists(atPath: cache.path))

        // The log has one entry, written by CleanCore, and the screen scanned again.
        let entry = try #require(world.app.logEntries.first)
        #expect(world.app.logEntries.count == 1)
        #expect(entry.action == .derivedDataDelete)
        #expect(entry.mode == .manual)
        #expect(CanonicalPath.same(URL(fileURLWithPath: entry.path), orphan))
        #expect(world.model.allRows.map(\.name).sorted() == ["Live-bbb", "ModuleCache.noindex"])
    }

    @Test func theSheetScansAgainSoAProjectThatCameBackIsNotListed() async throws {
        let world = try makeWorld()
        defer { world.home.remove() }
        let folder = try world.home.derivedDataEntry("Gone-aaa", workspace: goneWorkspace("Gone"))
        await world.model.refresh()
        let id = try #require(world.model.allRows.first?.id)
        #expect(world.model.allRows.first?.state == .orphaned, "the table is still the scan's")

        // The project is back (its info.plist names a workspace that exists) before the sheet opens.
        try world.home.rewritePlist(of: folder, workspace: "/usr/bin")
        let confirmation = await world.model.prepareDelete([id])

        #expect(confirmation.allowed.isEmpty)
        let item = try #require(confirmation.items.first)
        #expect(item.orphan == nil)
        #expect(item.state == .live)
        #expect(item.leftAloneReason?.contains("isn't orphaned") == true, "\(item.leftAloneReason ?? "")")
        let report = await world.model.confirmDelete(confirmation)
        #expect(report.outcomes.isEmpty)
        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(world.app.logEntries.isEmpty)
    }

    /// Review rule A: an orphan whose project reappears after the sheet opened is refused, not deleted.
    @Test func anOrphanWhoseProjectReappearsAfterTheSheetOpenedIsRefused() async throws {
        let world = try makeWorld()
        defer { world.home.remove() }
        let folder = try world.home.derivedDataEntry("Gone-aaa", workspace: goneWorkspace("Gone"))
        await world.model.refresh()
        world.model.selection = Set(world.model.allRows.map(\.id))
        await world.model.beginDelete()
        let confirmation = try #require(world.model.confirmation)
        #expect(confirmation.allowed.map(\.name) == ["Gone-aaa"])

        try world.home.rewritePlist(of: folder, workspace: "/usr/bin")
        let report = await world.model.confirmDelete(confirmation)

        let outcome = try #require(report.outcomes.first)
        guard case .refused(let why) = outcome.status else {
            Issue.record("expected a refusal, got \(outcome.status)")
            return
        }
        #expect(why.contains("project is back"), "\(why)")
        #expect(report.deletedCount == 0)
        #expect(report.summary == "Nothing was deleted. 1 folder was left alone.")
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "Build/blob").path))
        #expect(world.app.logEntries.isEmpty, "nothing happened, so nothing is logged")
        #expect(world.model.cleanupReport?.deletedCount == 0)
    }

    @Test func aFolderAddedAfterTheSheetOpenedIsNotDeleted() async throws {
        let world = try makeWorld()
        defer { world.home.remove() }
        let first = try world.home.derivedDataEntry("Gone-aaa", workspace: goneWorkspace("Gone"))
        await world.model.refresh()
        let confirmation = await world.model.prepareDelete(Set(world.model.allRows.map(\.id)))
        let later = try world.home.derivedDataEntry("Later-bbb", workspace: goneWorkspace("Later"))

        _ = await world.model.confirmDelete(confirmation)

        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: later.path), "it wasn't on the sheet")
        #expect(world.app.logEntries.count == 1)
        #expect(world.model.allRows.map(\.name) == ["Later-bbb"], "the screen scanned again and sees it")
    }

    @Test func aRefusedRootIsAnErrorWithNoDeleteButton() async throws {
        let world = try makeWorld()
        defer { world.home.remove() }
        // Xcode's own setting names the home folder as DerivedData.
        world.toolchain.customDerivedDataLocation = "~"
        try world.home.derivedDataEntry("Gone-aaa", workspace: goneWorkspace("Gone"))

        await world.model.refresh()

        let refusal = try #require(world.model.refusal)
        #expect(refusal.contains("home folder"), "\(refusal)")
        #expect(world.model.allRows.isEmpty, "nothing in a refused root is listed")
        #expect(!world.model.canDelete)
        world.model.selection = ["anything"]
        #expect(!world.model.canDelete, "nothing is deletable under a refused root")

        // Even asked for a folder, the sheet lists nothing as deletable.
        let confirmation = await world.model.prepareDelete([world.home.derivedDataRoot.appending(path: "Gone-aaa").path])
        #expect(confirmation.refusal != nil)
        #expect(confirmation.allowed.isEmpty)
    }

    @Test func onlyTheLocatedRootIsUsed() async throws {
        let world = try makeWorld()
        defer { world.home.remove() }
        let custom = world.home.url.appending(path: "Elsewhere/DerivedData", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: custom.appending(path: "Gone-zzz/Build"), withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["WorkspacePath": goneWorkspace("Zzz")], format: .xml, options: 0
        )
        try plist.write(to: custom.appending(path: "Gone-zzz/info.plist"))
        try world.home.derivedDataEntry("Default-aaa", workspace: goneWorkspace("Default"))

        world.toolchain.customDerivedDataLocation = custom.path
        await world.model.refresh()
        #expect(world.model.root == custom.path)
        #expect(world.model.allRows.map(\.name) == ["Gone-zzz"])

        world.toolchain.customDerivedDataLocation = nil
        await world.model.refresh()
        #expect(world.model.root == world.home.derivedDataRoot.path)
        #expect(world.model.allRows.map(\.name) == ["Default-aaa"])
    }

    @Test func aMissingRootIsNotAnError() async throws {
        let world = try makeWorld()
        defer { world.home.remove() }
        await world.model.refresh()
        #expect(world.model.rootMissing)
        #expect(world.model.refusal == nil)
        #expect(world.model.allRows.isEmpty)
    }
}
