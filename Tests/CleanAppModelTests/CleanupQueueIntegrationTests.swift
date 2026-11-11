@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Cleanup queue integration", .serialized)
@MainActor
struct CleanupQueueIntegrationTests {
    @Test func aWorktreeChangedWhileQueuedIsRefusedByItsOwnRecheck() async throws {
        let (world, app, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let queue = app.cleanupQueue
        let gate = QueueGate()
        defer { gate.open() }
        _ = queue.enqueue(title: "hold", unit: "items", work: [queueWork("hold") { await gate.wait(); return CleanupItemResult(.cleaned) }])
        #expect(await eventually { gate.entered })
        let path = try world.url("atlas-archive")
        let confirmation = await model.prepareRemoval(model.ids([path]))
        #expect(confirmation.allowed.count == 1)
        model.isShowingRemovalSheet = true
        let task = try #require(model.queueRemoval(confirmation))
        #expect(!model.isShowingRemovalSheet)
        #expect(queue.status(for: path.path)?.text == "Queued")
        #expect(model.queueRemoval(confirmation) == nil)
        try world.fixture.write("keep me\n", to: "new-work.txt", in: path)
        gate.open()
        #expect(await eventually { !queue.hasPending })
        #expect(task.cleanedCount == 0 && task.problemCount == 1)
        #expect(FileManager.default.fileExists(atPath: path.appending(path: "new-work.txt").path))
        #expect(task.items[0].result?.detail.contains("changed") == true)
        #expect(try RemovalLog(environment: app.environment).entries().isEmpty)
        #expect(queue.toasts.last?.needsReview == true && queue.selectedTask == nil)
    }

    @Test func stopAfterCurrentFolderLeavesTheOtherConfirmedFolders() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let aged = AgedRepos(fixture: fixture)
        let repo = try await aged.repo("project", days: 60, gitignore: "node_modules/\nbuild/\n.next/\n")
        for folder in ["node_modules", "build", ".next"] { try aged.blob(in: repo, folder + "/blob", kibibytes: 32) }
        let gate = ProcessGate(stage: "lsof")
        try gate.install(in: fixture.url, realGit: fixture.git.executable)
        defer { gate.open() }
        var environment = fixture.environment(scanRoots: [fixture.scanRoot]).withFakeTools()
        environment.tools.lsof = gate.lsof
        let app = AppModel(environment: environment, git: fixture.git)
        await app.refresh()
        let model = ProjectsModel(app: app)
        model.filter = .all
        await model.refresh()
        let confirmation = await model.prepareClean(Set(model.rows.map(\.id)))
        #expect(confirmation.folderCount == 3)
        gate.arm()
        let task = try #require(model.queueClean(confirmation))
        #expect(await eventually { gate.isWaiting })
        app.cleanupQueue.stop(task)
        gate.open()
        #expect(await eventually { !app.cleanupQueue.hasPending })
        #expect(task.state == .stopped && task.cleanedCount == 1)
        #expect(task.items.filter { $0.state == .stopped }.count == 2)
        #expect(try RemovalLog(environment: environment).entries().count == 1)
        let remaining = ["node_modules", "build", ".next"].filter { FileManager.default.fileExists(atPath: repo.appending(path: $0).path) }
        #expect(remaining.count == 2)
    }

    @Test func projectQueueRemeasuresOnlyTouchedProjectsAndTheirWorktreeSizes() async throws {
        let world = try await ProjectsWorld.make()
        defer { world.remove() }
        let model = world.projects
        model.filter = .all
        let chosen = try #require(world.row("delta"))
        let other = try #require(world.row("golf"))
        let before = try #require(world.app.scan?.sizes[chosen.worktree.path])
        let confirmation = await model.prepareClean([chosen.id])
        let scans = world.app.scanCount
        // A full project rescan would discover this; the task should rescan only its touched projects.
        try AgedRepos(fixture: world.fixture).blob(in: world.url("golf"), "build/new.bin", kibibytes: 128)
        let task = try #require(model.queueClean(confirmation))
        #expect(await eventually { !world.app.cleanupQueue.hasPending })
        #expect(task.cleanedCount == confirmation.folderCount)
        #expect(world.app.scanCount == scans)
        let after = try #require(world.app.scan?.sizes[chosen.worktree.path])
        #expect(after < before)
        #expect(world.row("delta") == nil || world.row("delta")?.project.folders.isEmpty == true)
        #expect(world.row("golf")?.project.folders.count == other.project.folders.count)
    }

    @Test func CLIIsRefusedDuringAQueuedTask() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let app = makeApp(fixture)
        let gate = QueueGate()
        defer { gate.open() }
        let task = try #require(app.cleanupQueue.enqueue(title: "hold", unit: "items", work: [queueWork("hold") {
            await gate.wait(); return CleanupItemResult(.cleaned)
        }]))
        #expect(await eventually { gate.entered })
        let result = try await CLIBinary.run(["prune", "--root", fixture.scanRoot.path, "--yes"], environment: [
            "BONSAI_SETTINGS_DIR": app.environment.settingsDirectory.path,
            "CLEAN_CLAUDE_SETTINGS_DIR": app.environment.settingsDirectory.path,
            "CLAUDE_CONFIG_DIR": app.environment.claudeConfigDirectory.path
        ])
        #expect(!result.succeeded && result.stderr.contains(CleanupLock.busyMessage))
        gate.open()
        #expect(await eventually { task.state == .done })
    }

    @Test func autoRunWaitsForAnEmptyQueue() async throws {
        let world = try await AutoWorld.make(enabledDaysAgo: 1)
        defer { world.remove() }
        let queue = world.app.cleanupQueue
        let gate = QueueGate()
        defer { gate.open() }
        _ = queue.enqueue(title: "hold", unit: "items", work: [queueWork("hold") { await gate.wait(); return CleanupItemResult(.cleaned) }])
        #expect(await eventually { gate.entered })
        var ended = false
        let run = Task { let result = await world.autoMode.runNow(); ended = true; return result }
        #expect(await eventually { !queue.emptyWaiters.isEmpty || ended })
        #expect(!ended, "auto clean must stay waiting while a manual task is pending")
        #expect(!world.app.isAutoRunning)
        #expect(try world.saved().lastAutoRun == nil)
        gate.open()
        let summary = await run.value
        #expect(summary?.reportOnly == true)
        #expect(try world.saved().lastAutoRun != nil)
    }

    @Test func notificationOnlyWhenMainWindowIsClosedAndPermissionIsOn() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let app = makeApp(fixture)
        let notifier = RecordingNotifier()
        let models = ScreenModels(app: app, notifier: notifier)
        let queue = models.app.cleanupQueue
        queue.windowIsVisible = true
        let first = try #require(queue.enqueue(title: "visible", unit: "items", work: [queueWork("first")]))
        #expect(await eventually { first.state == .done })
        #expect(notifier.posted.isEmpty)
        queue.windowIsVisible = false
        let second = try #require(queue.enqueue(title: "closed", unit: "items", work: [queueWork("second")]))
        #expect(await eventually { notifier.posted.count == 1 })
        #expect(notifier.posted.first?.body == second.summary)
        notifier.allowed = false
        let third = try #require(queue.enqueue(title: "off", unit: "items", work: [queueWork("third")]))
        #expect(await eventually { third.state == .done })
        #expect(notifier.posted.count == 1)
        #expect(notifier.authorizationRequests == 0)
    }
}
