@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Light clean through the model")
@MainActor
struct LightCleanModelTests {
    // MARK: - Deps column

    @Test func depsAreMeasuredForEveryRowIncludingMainCheckoutsWithASpinnerPerRow() async throws {
        let (world, app, model) = try await scannedDemoWorld()
        defer { world.remove() }
        // A main checkout with a node_modules of its own.
        let cobalt = try #require(world.repos.first { $0.lastPathComponent == "cobalt" })
        try world.fixture.write("x\n", to: "node_modules/left-pad/index.js", in: cobalt)
        #expect(model.allRows.allSatisfy { $0.dependencies == .notMeasured })
        #expect(model.allRows.allSatisfy { $0.dependencyText == "–" })

        let task = Task { await model.computeDependenciesIfNeeded() }
        var sawSpinner = false
        while !task.isCancelled {
            if model.allRows.contains(where: { $0.dependencies.isMeasuring }) { sawSpinner = true }
            if !model.isMeasuringDependencies, model.hasRequestedDependencies { break }
            await Task.yield()
        }
        await task.value
        #expect(sawSpinner, "each row shows a spinner until its number is in")
        #expect(!model.isMeasuringDependencies)
        #expect(model.allRows.allSatisfy { !$0.dependencies.isMeasuring })

        let web = try #require(model.row(try world.url("cobalt-web")))
        #expect((web.dependencyBytes ?? 0) > 19 * 1024 * 1024, "the 20 MB node_modules: \(web.dependencyText)")
        #expect(web.dependencyText != "–")
        let main = try #require(model.row(cobalt))
        #expect(main.worktree.isMain)
        #expect(main.dependencyBytes != nil, "main checkouts are measured too")
        let archive = try #require(model.row(try world.url("atlas-archive")))
        #expect(archive.dependencies == .measured(nil), "nothing to clean there")
        let gone = try #require(model.row(try world.url("beacon-gone")))
        #expect(gone.dependencies == .measured(nil), "a missing folder has nothing to clean")
        #expect(app.assessments.count == model.allRows.count)

        // Measured once on first appearance; the toolbar button measures again.
        let before = model.dependencySizes
        await model.computeDependenciesIfNeeded()
        #expect(model.dependencySizes == before)
        try FileManager.default.removeItem(at: cobalt.appending(path: "node_modules"))
        await model.computeDependencies()
        #expect(model.row(cobalt)?.dependencies == .measured(nil))
    }

    // MARK: - The sheet

    @Test func theConfirmationListsCandidatesAndSkippedFoldersAndMainCheckouts() async throws {
        let (world, _, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let cobalt = try #require(world.repos.first { $0.lastPathComponent == "cobalt" })
        try world.fixture.write("x\n", to: "node_modules/pkg/index.js", in: cobalt)
        let ids = model.ids([
            try world.url("cobalt-web"), try world.url("cobalt-swift"), try world.url("cobalt-py"),
            try world.url("atlas-archive"), cobalt,
        ])

        let confirmation = await model.prepareLightClean(ids)

        #expect(confirmation.items.count == 5)
        let byName = Dictionary(uniqueKeysWithValues: confirmation.items.map { ($0.worktree.url.lastPathComponent, $0) })
        let web = try #require(byName["cobalt-web"])
        #expect(web.candidates.map(\.relativePath) == ["node_modules"])
        #expect((web.candidates.first?.estimatedBytes ?? 0) > 19 * 1024 * 1024)
        let swift = try #require(byName["cobalt-swift"])
        #expect(swift.candidates.map(\.relativePath) == [".build"])
        #expect(swift.candidates.first?.packageClones == ["checkouts/demo-kit"])
        let main = try #require(byName["cobalt"])
        #expect(main.worktree.isMain)
        #expect(main.candidates.map(\.relativePath) == ["node_modules"], "main checkouts are included")

        // cobalt-py: .venv holds a clone with an unpushed commit, so it is listed as skipped, with why.
        let python = try #require(byName["cobalt-py"])
        #expect(python.candidates.isEmpty)
        let skip = try #require(python.skipped.first { $0.relativePath == ".venv" })
        guard case .nestedCheckout = skip.reason else {
            Issue.record("expected a nested checkout, got \(skip.reason)")
            return
        }
        #expect(python.leftAloneReason == "Every folder found here is left alone.")
        #expect(byName["atlas-archive"]?.isCleanable == false)
        #expect(byName["atlas-archive"]?.leftAloneReason == "No dependency or build folders to delete.")

        #expect(Set(confirmation.cleanable.map { $0.worktree.url.lastPathComponent }) == ["cobalt-web", "cobalt-swift", "cobalt"])
        #expect(Set(confirmation.others.map { $0.worktree.url.lastPathComponent }) == ["cobalt-py", "atlas-archive"])
        #expect(confirmation.folderCount == 3)
        #expect(confirmation.deleteButtonTitle == "Delete 3 folders")
        #expect(confirmation.estimatedTotalBytes > 19 * 1024 * 1024)
        #expect(LightCleanConfirmation.nextTimeLine
            == "Next time you use it, run npm ci / pod install / flutter pub get as needed.")
        // Looking deletes nothing.
        #expect(FileManager.default.fileExists(atPath: try world.url("cobalt-web").appending(path: "node_modules").path))
    }

    @Test func runningItCallsTheCleanerAndRefreshesTheRow() async throws {
        let (world, app, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let web = try world.url("cobalt-web")
        await model.computeDependencies()
        #expect((model.row(web)?.dependencyBytes ?? 0) > 19 * 1024 * 1024)
        let scans = app.scanCount
        model.selection = model.ids([web])

        await model.beginLightClean()
        #expect(model.isShowingLightCleanSheet)
        #expect(!model.isPreparingLightClean)
        let confirmation = try #require(model.lightCleanConfirmation)
        #expect(confirmation.folderCount == 1)
        let report = await model.confirmLightClean(confirmation)

        #expect(report.deletedCount == 1)
        #expect(report.notDeletedCount == 0)
        #expect(report.summary.hasPrefix("Deleted 1 folder"), "\(report.summary)")
        let outcome = try #require(report.outcomes.first)
        #expect(outcome.error == nil)
        guard case .deleted(let freed)? = outcome.folders.first?.status else {
            Issue.record("expected deleted, got \(String(describing: outcome.folders.first?.status))")
            return
        }
        #expect(freed != nil, "measured around the delete")
        #expect(!FileManager.default.fileExists(atPath: web.appending(path: "node_modules").path))
        #expect(FileManager.default.fileExists(atPath: web.appending(path: "notes/web.md").path), "tracked files stay")

        // The log entry came from CleanCore; the cleaned worktree alone was measured again (no full rescan), so
        // its size and dependency folders are fresh.
        let entry = try #require(app.logEntries.first)
        #expect(app.logEntries.count == 1)
        #expect(entry.action == .lightClean)
        #expect(entry.mode == .manual)
        #expect(entry.path.hasSuffix("cobalt-web/node_modules"))
        #expect(app.scanCount == scans, "no full rescan after a light clean")
        #expect((model.row(web)?.sizeBytes ?? .max) < 1024 * 1024, "the 20 MB of node_modules are gone from its size")
        #expect(model.row(web)?.isMeasuringSize == false)
        #expect(model.row(web)?.dependencies == .measured(nil))
        #expect(model.row(web)?.dependencyText == "–")
        #expect(model.lightCleanReport?.deletedCount == 1)
        #expect(!model.isLightCleaning)

        model.dismissLightClean()
        #expect(!model.isShowingLightCleanSheet)
        #expect(model.lightCleanConfirmation == nil && model.lightCleanReport == nil)
    }

    // MARK: - Only what the sheet listed (review rule A)

    @Test func aNestedCheckoutAddedToAFolderAfterTheSheetOpenedIsRefused() async throws {
        let (world, app, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let web = try world.url("cobalt-web")
        let confirmation = await model.prepareLightClean(model.ids([web]))
        #expect(confirmation.cleanable.first?.candidates.map(\.relativePath) == ["node_modules"])

        // After the sheet listed it, a clone with an unpushed commit appears inside node_modules.
        let nested = web.appending(path: "node_modules/mypkg")
        try await world.fixture.run(["init", "--quiet"], in: web.appending(path: "node_modules"))
        try FileManager.default.removeItem(at: web.appending(path: "node_modules/.git"))
        try await world.fixture.makeRepo("mypkg", in: web.appending(path: "node_modules"))
        try world.fixture.write("mine\n", to: "local.txt", in: nested)
        try await world.fixture.commitAll(in: nested, message: "Local work")

        let report = await model.confirmLightClean(confirmation)

        #expect(report.deletedCount == 0)
        let folder = try #require(report.outcomes.first?.folders.first)
        guard case .refused(let why) = folder.status else {
            Issue.record("expected a refusal, got \(folder.status)")
            return
        }
        #expect(why.contains("Another git checkout is inside"), "\(why)")
        #expect(FileManager.default.fileExists(atPath: nested.appending(path: "local.txt").path), "the local work is intact")
        #expect(FileManager.default.fileExists(atPath: web.appending(path: "node_modules/left-pad/index.js").path))
        #expect(app.logEntries.isEmpty, "nothing was deleted, so nothing is logged")
        #expect(report.summary == "Nothing was deleted. 1 folder was left alone.")
    }

    @Test func aFolderCreatedAfterTheSheetOpenedIsNotDeleted() async throws {
        let (world, _, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let web = try world.url("cobalt-web")
        let confirmation = await model.prepareLightClean(model.ids([web]))
        #expect(confirmation.cleanable.first?.candidates.map(\.relativePath) == ["node_modules"])

        // A regenerable folder that didn't exist when the sheet listed the folders.
        try world.fixture.write("x\n", to: ".venv/lib/x.py", in: web)
        try world.fixture.write("x\n", to: "packages/app/node_modules/y/index.js", in: web)
        _ = await model.confirmLightClean(confirmation)

        #expect(!FileManager.default.fileExists(atPath: web.appending(path: "node_modules").path))
        #expect(FileManager.default.fileExists(atPath: web.appending(path: ".venv/lib/x.py").path))
        #expect(FileManager.default.fileExists(atPath: web.appending(path: "packages/app/node_modules/y/index.js").path))
    }

    @Test func aProcessInsideBlocksTheWorktreeInTheSheetAndAtConfirmTime() async throws {
        let (world, app, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let web = try world.url("cobalt-web")
        let shell = SleepingProcess()
        defer { shell.stop() }

        // Open the sheet, then start a process inside: the cleaner's own re-check stops it.
        let confirmation = await model.prepareLightClean(model.ids([web]))
        #expect(confirmation.cleanable.count == 1)
        try shell.start(in: web)
        let report = await model.confirmLightClean(confirmation)
        #expect(report.deletedCount == 0)
        let outcome = try #require(report.outcomes.first)
        #expect(outcome.error?.contains("working folder inside") == true, "\(outcome.error ?? "")")
        #expect(FileManager.default.fileExists(atPath: web.appending(path: "node_modules").path))
        #expect(app.logEntries.isEmpty)

        // With the process still there, a new sheet lists the worktree as left alone, with the process.
        let again = await model.prepareLightClean(model.ids([web]))
        #expect(again.cleanable.isEmpty)
        let item = try #require(again.items.first)
        #expect(item.blocker?.contains(SleepingProcess.command) == true, "\(item.blocker ?? "")")
        #expect(item.candidates.isEmpty)
    }

    @Test func aStaleRecordIsLeftAloneAndItsFolderIsNotCleanedAsItsRow() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let alpha = try await fixture.makeRepo("alpha")
        let bravo = try await fixture.makeRepo("bravo")
        try fixture.write("node_modules/\n", to: ".gitignore", in: bravo)
        try await fixture.commitAll(in: bravo, message: "Ignore node_modules")
        try await fixture.run(["push", "--quiet", "origin", "main"], in: bravo)
        let shared = fixture.scanRoot.appending(path: "shared", directoryHint: .isDirectory)
        try await fixture.addWorktree(to: alpha, at: shared, branch: "a-task")
        try FileManager.default.removeItem(at: shared)
        try await fixture.addWorktree(to: bravo, at: shared, branch: "b-task")
        try fixture.write("x\n", to: "node_modules/pkg/index.js", in: shared)
        let app = makeApp(fixture, root: fixture.scanRoot)
        await app.refresh()
        let model = showingAll(WorktreesModel(app: app))
        let stale = try #require(model.allRows.first { $0.repoName == "alpha" && $0.url.lastPathComponent == "shared" })
        let real = try #require(model.allRows.first { $0.repoName == "bravo" && $0.url.lastPathComponent == "shared" })
        #expect(stale.isStaleRecord)

        let confirmation = await model.prepareLightClean([stale.id, real.id])

        let staleItem = try #require(confirmation.items.first { $0.id == stale.id })
        #expect(staleItem.candidates.isEmpty)
        #expect(staleItem.leftAloneReason?.contains("another repo's folder") == true, "\(staleItem.leftAloneReason ?? "")")
        let realItem = try #require(confirmation.items.first { $0.id == real.id })
        #expect(realItem.candidates.map(\.relativePath) == ["node_modules"])

        await model.computeDependencies()
        #expect(model.allRows.first { $0.id == stale.id }?.dependencies == .measured(nil))
        #expect((model.allRows.first { $0.id == real.id }?.dependencyBytes ?? 0) > 0)
    }

    @Test func oneCleanupAtATime() async throws {
        let (world, _, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let web = try world.url("cobalt-web")
        let confirmation = await model.prepareLightClean(model.ids([web]))
        let finished = await model.app.cleaningUp { await model.confirmLightClean(confirmation) }
        let report = try #require(finished)
        #expect(report.deletedCount == 0)
        #expect(report.outcomes.first?.error?.contains("another cleanup is still running") == true)
        #expect(FileManager.default.fileExists(atPath: web.appending(path: "node_modules").path))
    }
}
