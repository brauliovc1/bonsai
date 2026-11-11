@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Downloads and Trash model", .serialized)
@MainActor
struct DownloadsTrashModelTests {
    @Test func scanIsReadOnlyAndMoveRequiresTheCapturedConfirmation() async throws {
        let world = try DownloadsModelWorld()
        defer { world.fixture.remove() }
        let file = try world.file("old.zip")
        let model = world.model()
        await model.refresh()
        #expect(model.eligible.count == 1 && model.readyBytes == 7)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(model.queueMove(DownloadsConfirmation(files: model.eligible)) == nil)
        model.selectAllReady()
        model.prepareMove()
        let confirmation = try #require(model.moveConfirmation)
        let task = try #require(model.queueMove(confirmation))
        #expect(model.queueMove(confirmation) == nil)
        #expect(model.moveConfirmation == nil && model.selection.isEmpty)
        #expect(await eventually { !world.app.cleanupQueue.hasPending })
        #expect(task.cleanedCount == 1 && task.measuredFreedBytes == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: world.trash.appending(path: "old.zip").path))
        #expect(world.app.logEntries.map(\.action) == [.movedToTrash])
        #expect(model.readyBytes == 0)
        let history = RemovalsModel(app: world.app)
        let row = try #require(history.rows.first)
        #expect(history.putBackUnavailableReason(row) == nil)
        let restore = try #require(history.queuePutBack(row.id))
        #expect(await eventually { !world.app.cleanupQueue.hasPending })
        #expect(restore.cleanedCount == 1)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(world.app.logEntries.map(\.action) == [.movedToTrash, .putBack])
    }

    @Test func queuedMoveWaitsForTheLockThenRefusesAChangedFile() async throws {
        let world = try DownloadsModelWorld()
        defer { world.fixture.remove() }
        let file = try world.file("old.zip")
        let model = world.model()
        await model.refresh()
        let lock = try #require(try CleanupLock.tryAcquire(environment: world.app.environment))
        defer { lock.release() }
        model.selectAllReady(); model.prepareMove()
        let confirmation = try #require(model.moveConfirmation)
        let task = try #require(model.queueMove(confirmation))
        #expect(await eventually { task.state == .waiting })
        #expect(FileManager.default.fileExists(atPath: file.path))
        try Data("changed after confirmation".utf8).write(to: file)
        lock.release()
        #expect(await eventually { !world.app.cleanupQueue.hasPending })
        #expect(task.items.first?.state == .refused)
        #expect(world.app.logEntries.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func emptyTrashCannotRunUntilItsOwnConfirmationAndDenialIsActionable() async throws {
        let world = try DownloadsModelWorld()
        defer { world.fixture.remove() }
        try Data("fixture".utf8).write(to: world.trash.appending(path: "old.zip"))
        let fake = ModelTrashEmptier()
        fake.denied = true
        let model = world.model(emptier: fake)
        await model.refresh()
        #expect(model.canEmptyTrash)
        #expect(model.confirmEmptyTrash() == nil && fake.calls == 0)
        await model.prepareEmptyTrash()
        #expect(model.emptyConfirmation.contains("Permanently delete 1 item"))
        let task = try #require(model.confirmEmptyTrash())
        #expect(await eventually { !world.app.cleanupQueue.hasPending })
        #expect(fake.calls == 1 && model.automationDenied)
        #expect(task.items.first?.state == .failed && world.app.logEntries.isEmpty)
        fake.denied = false
        await model.prepareEmptyTrash()
        _ = try #require(model.confirmEmptyTrash())
        #expect(await eventually { !world.app.cleanupQueue.hasPending })
        #expect(fake.calls == 2 && !model.automationDenied)
        #expect(world.app.logEntries.map(\.action) == [.trashEmptied])
        // The fake never deletes even the fixture's Trash file.
        #expect(FileManager.default.fileExists(atPath: world.trash.appending(path: "old.zip").path))
    }

    @Test func oneTotalCountsDownloadsOnceAndExcludesTrashAndSnapshots() async throws {
        let world = try DownloadsModelWorld()
        defer { world.fixture.remove() }
        _ = try world.file("old.zip")
        try Data(repeating: 42, count: 10000).write(to: world.trash.appending(path: "big.zip"))
        let model = world.model()
        await model.refresh()
        let models = ScreenModels(app: world.app, runner: world.runner)
        let summary = ReclaimSummary(app: world.app, projects: models.projects, caches: models.caches,
                                    derivedData: models.derivedData, dockerSimulators: models.dockerSimulators, downloads: model)
        #expect(summary.totalBytes == 7 && summary.count(.downloads) == 1)
        #expect(summary.partsHelp.contains("Downloads: "))
        #expect(SidebarSection.downloads.badge(in: summary) == DisplayText.bytes(7))
        #expect(OverviewCategory.downloads.parts == [.downloads])
        #expect(SidebarSection.Group.cleanUp.sections.firstIndex(of: .downloads)
                == SidebarSection.Group.cleanUp.sections.firstIndex(of: .caches).map { $0 + 1 })
        let overview = OverviewModel(app: world.app, worktrees: models.worktrees, projects: models.projects,
            derivedData: models.derivedData, dockerSimulators: models.dockerSimulators, caches: models.caches,
            downloads: model, autoMode: models.autoMode, navigation: models.navigation)
        #expect(overview.card(.downloads)?.bytes == 7)
        overview.open(.downloads)
        #expect(models.navigation.section == .downloads && model.selected.count == 1)
    }

    @Test func unreadableTrashConfirmationNeverClaimsAnEmptyTrash() throws {
        let world = try DownloadsModelWorld()
        defer { world.fixture.remove() }
        let model = world.model()
        let listing = try JSONDecoder().decode(DownloadsListing.self, from: Data("""
        {"downloads":{"files":[],"warnings":[]},"trash":{},"timeMachine":{"snapshots":[],"warnings":[]}}
        """.utf8))
        model.listing = listing
        #expect(model.canEmptyTrash)
        #expect(model.emptyConfirmation == "Permanently delete everything in the Trash? This can't be undone.")
    }

    @Test func filesArrivingAfterTheEmptyConfirmationNeverReachFinder() async throws {
        let world = try DownloadsModelWorld()
        defer { world.fixture.remove() }
        try Data("confirmed".utf8).write(to: world.trash.appending(path: "confirmed.zip"))
        let fake = ModelTrashEmptier()
        let model = world.model(emptier: fake)
        await model.refresh()
        await model.prepareEmptyTrash()
        #expect(model.emptyConfirmation.contains("1 item"))
        let lock = try #require(try CleanupLock.tryAcquire(environment: world.app.environment))
        defer { lock.release() }
        let task = try #require(model.confirmEmptyTrash())
        #expect(await eventually { task.state == .waiting })
        try Data("never confirmed".utf8).write(to: world.trash.appending(path: "new.zip"))
        lock.release()
        #expect(await eventually { !world.app.cleanupQueue.hasPending })
        #expect(fake.calls == 0 && world.app.logEntries.isEmpty)
        #expect(task.items.first?.result?.detail.contains("changed since you confirmed") == true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: world.trash.path).count == 2)
    }

    @Test func editsDeepInsideTrashInvalidateItsConfirmation() async throws {
        let world = try DownloadsModelWorld()
        defer { world.fixture.remove() }
        let file = world.trash.appending(path: "folder/nested/keep.txt")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("before".utf8).write(to: file)
        let fake = ModelTrashEmptier()
        let model = world.model(emptier: fake)
        await model.refresh()
        await model.prepareEmptyTrash()
        try Data("after!".utf8).write(to: file)
        let task = try #require(model.confirmEmptyTrash())
        #expect(await eventually { !world.app.cleanupQueue.hasPending })
        #expect(fake.calls == 0 && world.app.logEntries.isEmpty)
        #expect(task.items.first?.result?.detail.contains("changed since you confirmed") == true)
        #expect(try String(contentsOf: file, encoding: .utf8) == "after!")
    }
}

@MainActor
private struct DownloadsModelWorld {
    let fixture: GitFixture
    let app: AppModel
    var downloads: URL { app.environment.homeDirectory.appending(path: "Downloads") }
    var trash: URL { app.environment.homeDirectory.appending(path: ".Trash") }
    init() throws {
        fixture = try GitFixture()
        app = makeApp(fixture)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    }
    func file(_ name: String) throws -> URL {
        let url = downloads.appending(path: name)
        try Data("fixture".utf8).write(to: url)
        return url
    }
    var runner: CommandRunner {
        CommandRunner { url, _, _ in
            let output = url.lastPathComponent == "hdiutil" ? "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>images</key><array/></dict></plist>"
                : url.lastPathComponent == "tmutil" ? "Snapshots for volume group containing disk /:\ncom.apple.TimeMachine.2026-10-01-100000.local\n" : "16\tfixture\n"
            return ProcessResult(exitCode: 0, stdout: Data(output.utf8), stderr: "", timedOut: false)
        }
    }
    func model(emptier: any TrashEmptier = UnavailableTrashEmptier()) -> DownloadsTrashModel {
        let directory = trash
        let environment = app.environment
        let old = environment.now().addingTimeInterval(-31 * 86400)
        let operation = TrashOperation { source in
            #expect(try CleanupLock.tryAcquire(environment: environment) == nil)
            let destination = directory.appending(path: source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        }
        return DownloadsTrashModel(app: app, runner: runner, trash: operation, emptier: emptier, dateAdded: { _ in old })
    }
}

@MainActor
private final class ModelTrashEmptier: TrashEmptier {
    var calls = 0
    var denied = false
    func empty() async throws {
        calls += 1
        if denied { throw TrashEmptyError.automationDenied }
    }
}
