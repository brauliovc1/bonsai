import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Remove, prune and restore through the models")
@MainActor
struct RemovalFlowTests {
    @Test func confirmRemovalRemovesOnlyAllowedItems() async throws {
        let (world, app, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let archive = try world.url("atlas-archive")
        let wip = try world.url("atlas-wip")
        let scans = app.scanCount
        model.selection = model.ids([archive, wip])

        await model.beginRemoval()
        #expect(model.isShowingRemovalSheet)
        #expect(!model.isPreparingRemoval)
        let confirmation = try #require(model.confirmation)
        #expect(confirmation.allowed.count == 1)
        let outcomes = await model.confirmRemoval(confirmation)

        #expect(outcomes.map(\.item.worktree.url.lastPathComponent) == ["atlas-archive"])
        let outcome = try #require(outcomes.first)
        #expect(outcome.removed, "\(outcome.error ?? "")")
        #expect(outcome.warnings.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: archive.path))
        #expect(FileManager.default.fileExists(atPath: wip.appending(path: "scratch.md").path), "blocked: untouched")

        #expect(app.scanCount == scans + 1, "rescanned after the removal")
        #expect(model.row(archive) == nil)
        #expect(model.row(wip) != nil)
        #expect(model.selection == model.ids([wip]))
        #expect(model.report?.removedCount == 1)
        #expect(model.report?.summary.hasPrefix("Removed 1 worktree") == true)
        #expect(!model.isRemoving)

        let entry = try #require(app.logEntries.last)
        #expect(app.logEntries.count == 1)
        #expect(entry.action == .worktreeRemove)
        #expect(entry.mode == .manual)
        #expect(entry.branch == "archive")
        #expect(CanonicalPath.same(URL(fileURLWithPath: entry.path), archive))
        let branch = try await world.fixture.run(["branch", "--list", "archive"], in: world.repos[0])
        #expect(branch.contains("archive"), "the branch is kept")

        model.dismissRemoval()
        #expect(!model.isShowingRemovalSheet)
        #expect(model.confirmation == nil)
        #expect(model.report == nil)
    }

    @Test func theRecheckRightBeforeRemovingStillRefuses() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let repo = try await fixture.makeRepo("solo")
        let task = try await fixture.addSiblingWorktree(to: repo, name: "task")
        let app = makeApp(fixture, root: fixture.scanRoot)
        await app.refresh()
        let model = showingAll(WorktreesModel(app: app))
        let confirmation = await model.prepareRemoval(model.ids([task]))
        #expect(confirmation.allowed.count == 1)

        try fixture.write("new work\n", to: "after-the-sheet-opened.txt", in: task)
        let outcomes = await model.confirmRemoval(confirmation)
        let outcome = try #require(outcomes.first)
        #expect(!outcome.removed)
        #expect(outcome.changedSinceConfirmed)
        #expect(outcome.error?.contains("uncommitted") == true, "\(outcome.error ?? "")")
        #expect(FileManager.default.fileExists(atPath: task.appending(path: "after-the-sheet-opened.txt").path))
        #expect(app.logEntries.isEmpty)
        #expect(model.report?.failedCount == 1)
    }

    @Test func pruneClearsMissingFolders() async throws {
        let (world, app, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let gone = try world.url("beacon-gone")
        #expect(model.missingFolderRows.map(\.url.lastPathComponent) == ["beacon-gone"])

        let plan = await model.preparePrune()
        #expect(plan.repos.map(\.repoName) == ["beacon"])
        #expect(plan.entryCount == 1)
        let outcomes = await model.prune(plan)
        let outcome = try #require(outcomes.first)
        #expect(outcomes.count == 1)
        #expect(outcome.repoName == "beacon")
        #expect(outcome.pruned.count == 1)
        #expect(outcome.refusals.isEmpty)
        #expect(outcome.summary == "beacon: cleared git's record of 1 missing folder.")
        #expect(model.row(gone) == nil)
        #expect(model.missingFolderRows.isEmpty)
        #expect(app.logEntries.map(\.action) == [.worktreePrune])
        #expect(model.pruneOutcomes?.count == 1)
    }

    @Test func restoreRoundTrip() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let repo = try await fixture.makeRepo("solo")
        let first = try await fixture.addSiblingWorktree(to: repo, name: "first")
        let second = try await fixture.addSiblingWorktree(to: repo, name: "second")
        let app = makeApp(fixture, root: fixture.scanRoot)
        await app.refresh()
        let worktrees = showingAll(WorktreesModel(app: app))
        let removals = RemovalsModel(app: app)
        #expect(removals.rows.isEmpty)

        await worktrees.confirmRemoval(await worktrees.prepareRemoval(worktrees.ids([first])))
        await worktrees.confirmRemoval(await worktrees.prepareRemoval(worktrees.ids([second])))
        #expect(removals.rows.map(\.branchText) == ["second", "first"], "newest first")
        #expect(removals.rows.allSatisfy { $0.isRestorable })
        #expect(worktrees.allRows.count == 1)

        let row = try #require(removals.rows.last)
        let message = await removals.restore(row.id)
        #expect(!message.isError, "\(message.text)")
        #expect(message.text.contains(Restorer.dependenciesNote))
        #expect(message.text.contains("branch first"))
        #expect(removals.message == message)
        #expect(removals.restoringID == nil)
        #expect(FileManager.default.fileExists(atPath: first.appending(path: "README.md").path))
        #expect(worktrees.row(first) != nil, "rescanned after the restore")
        let restored = try #require(removals.rows.first { $0.id == row.id })
        #expect(!restored.isRestorable)
        #expect(restored.restoredAt != nil)

        let again = await removals.restore(row.id)
        #expect(again.isError)
        #expect(again.text.contains("already restored"))
    }
}
