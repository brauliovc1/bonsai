@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// PLAN §4.8 and §8.4 in the app: Remove anyway for ONE blocked worktree from its details panel (or More with
/// that one row selected), its sheet, its log row and Restore; and every other way in, which never reaches it.
@Suite("Remove anyway in the app")
@MainActor
struct RemoveAnywayModelTests {
    @Test func oneBlockedRowFromItsDetailsToRecentlyRemovedAndBack() async throws {
        let (world, app, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let wip = try world.url("atlas-wip")
        model.selection = model.ids([wip])
        let row = try #require(model.selectedRows.first)
        #expect(!row.canRemove && row.offersRemoveAnyway)
        #expect(row.removeAnywayUnavailableText == nil)
        #expect(!model.canRemoveSelection, "Remove… stays disabled for a blocked row")
        #expect(model.removeDisabledReason?.hasSuffix(" " + RemoveAnywayText.detailsHint) == true, "\(model.removeDisabledReason ?? "")")
        #expect(model.canRemoveAnyway && model.removeAnywayRow?.id == row.id)
        #expect(model.removeAnywayHelp.hasSuffix("Lost: 2 uncommitted files."))

        await model.beginRemoveAnyway()
        #expect(model.isShowingRemoveAnywaySheet && !model.isPreparingRemoveAnyway)
        let confirmation = try #require(model.removeAnywayConfirmation)
        #expect(confirmation.title == "Remove \u{201C}wip\u{201D} anyway?")
        #expect(confirmation.line == "These are deleted for good. Bonsai can't bring them back. The branch is kept.")
        #expect(confirmation.lossList.entries(.uncommittedFiles).map(\.text) == ["README.md", "scratch.md"])
        #expect(!model.removeAnywayUnderstood, "the checkbox starts off")

        // Without the checkbox nothing happens.
        #expect(await model.confirmRemoveAnyway(confirmation, understood: false) == nil)
        #expect(FileManager.default.fileExists(atPath: wip.appending(path: "scratch.md").path))

        model.removeAnywayUnderstood = true
        let outcome = try #require(await model.confirmRemoveAnyway(confirmation, understood: model.removeAnywayUnderstood))
        #expect(outcome.removed, "\(outcome.text)")
        #expect(outcome.text.contains("Its branch wip is kept."))
        #expect(!FileManager.default.fileExists(atPath: wip.path))
        #expect(model.selection.isEmpty)
        #expect(model.row(wip) == nil, "the row goes at once")

        let entry = try #require(app.logEntries.last)
        let logRow = RemovalLogRow(entry: entry)
        #expect(logRow.actionText == "Removed anyway")
        #expect(logRow.lossLine == "Lost: 2 uncommitted files.")
        #expect(logRow.isRestorable)

        let message = await RemovalsModel(app: app).restore(entry.id)
        #expect(!message.isError, "\(message.text)")
        #expect(message.text.contains(Restorer.lostFilesNote))
        #expect(FileManager.default.fileExists(atPath: wip.appending(path: ".git").path))
        #expect(!FileManager.default.fileExists(atPath: wip.appending(path: "scratch.md").path), "the lost file stays lost")
    }

    /// Several rows, Remove…, the Delete key, Remove all N and a repo folder never reach it.
    @Test func noOtherWayReachesIt() async throws {
        let (world, _, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let wip = try world.url("atlas-wip")
        let archive = try world.url("atlas-archive")

        // Two rows selected, one of them offered: no Remove anyway (one at a time).
        model.selection = model.ids([wip, archive])
        #expect(model.removeAnywayRow == nil && !model.canRemoveAnyway)
        await model.beginRemoveAnyway()
        #expect(!model.isShowingRemoveAnywaySheet && model.removeAnywayConfirmation == nil)
        #expect(model.removeAnywayHelp.hasPrefix("Select one blocked worktree"))

        // Remove… and the Delete key with both selected: the sheet lists wip as blocked and removes only archive.
        await model.removeSelection()
        let confirmation = try #require(model.confirmation)
        #expect(confirmation.blocked.map(\.worktree.url.lastPathComponent) == ["atlas-wip"])
        let outcomes = await model.confirmRemoval(confirmation)
        #expect(outcomes.map(\.item.worktree.url.lastPathComponent) == ["atlas-archive"])
        #expect(FileManager.default.fileExists(atPath: wip.appending(path: "scratch.md").path))
        model.dismissRemoval()

        // wip alone: Remove… (and Delete) open nothing; asking by id opens nothing either.
        model.selection = model.ids([wip])
        await model.removeSelection()
        #expect(!model.isShowingRemovalSheet)
        await model.beginRemoval(model.ids([wip]))
        #expect(!model.isShowingRemovalSheet)

        // Remove all N on the header leaves it out.
        let atlas = try #require(model.groups.first { $0.name == "atlas" })
        #expect(!atlas.removableRows.contains { CanonicalPath.same($0.url, wip) })

        // The repo folder selected: nothing.
        let main = try #require(model.allRows.first { $0.worktree.isMain && $0.repoName == "atlas" })
        model.selection = [main.id]
        #expect(model.removeAnywayRow == nil)
        await model.beginRemoveAnyway()
        #expect(!model.isShowingRemoveAnywaySheet)
        #expect(FileManager.default.fileExists(atPath: wip.appending(path: "scratch.md").path))
        #expect(!(model.app.logEntries.contains { $0.action == .worktreeRemoveAnyway }))
    }

    /// A row that holds something listable but also a blocker it never overrides says what to do instead; the
    /// fresh look refuses a row that became one after the scan.
    @Test func aNeverOverridableBlockerSaysWhatToDoInstead() async throws {
        let (world, app, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let wip = try world.url("atlas-wip")
        model.selection = model.ids([wip])
        try await world.fixture.lock(wip, in: world.repos[0], reason: "on a drive")

        await model.beginRemoveAnyway()
        #expect(model.removeAnywayConfirmation == nil)
        #expect(model.removeAnywayRefusal == RemoveAnywayText.instead(for: .locked(reason: "on a drive")))
        model.dismissRemoveAnyway()

        await app.refresh()
        let row = try #require(model.row(wip))
        #expect(!row.offersRemoveAnyway)
        #expect(row.removeAnywayUnavailableText == "Remove anyway isn't available: It's locked. Unlock it with git "
            + "worktree unlock first; Remove anyway never overrides a lock.")
        #expect(model.removeAnywayRow == nil)
    }

    /// Changed between the confirmation and the delete: "It changed since you confirmed. Look again."
    @Test func aChangeAfterTheConfirmationIsRefused() async throws {
        let (world, _, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let wip = try world.url("atlas-wip")
        model.selection = model.ids([wip])
        await model.beginRemoveAnyway()
        let confirmation = try #require(model.removeAnywayConfirmation)
        try world.fixture.write("more\n", to: "later.md", in: wip)

        let outcome = try #require(await model.confirmRemoveAnyway(confirmation, understood: true))
        #expect(!outcome.removed)
        #expect(outcome.text == "It changed since you confirmed. Look again.")
        #expect(outcome.changes.contains { $0.contains("later.md") }, "\(outcome.changes)")
        #expect(FileManager.default.fileExists(atPath: wip.appending(path: "scratch.md").path))
    }

    /// Under another cleanup (the app's guard, or `cleanup.lock` held by another process) it is refused with the
    /// usual message and nothing is touched.
    @Test func underAnotherCleanupItIsRefused() async throws {
        let (world, app, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let wip = try world.url("atlas-wip")
        model.selection = model.ids([wip])
        await model.beginRemoveAnyway()
        let confirmation = try #require(model.removeAnywayConfirmation)

        let lock = try #require(try CleanupLock.tryAcquire(environment: app.environment))
        let locked = try #require(await model.confirmRemoveAnyway(confirmation, understood: true))
        lock.release()
        #expect(locked.text == "Not removed: \(CleanupPresentation.busyReason).")

        let gate = Gate()
        let other = Task { await app.cleaningUp { await gate.wait() } }
        while !app.isCleaningUp { await Task.yield() }
        #expect(model.canRemoveAnyway, "another task no longer disables this row; the UI can queue it")
        let busy = try #require(await model.confirmRemoveAnyway(confirmation, understood: true))
        await gate.open()
        _ = await other.value
        #expect(busy.text == "Not removed: another cleanup is still running.")
        #expect(FileManager.default.fileExists(atPath: wip.appending(path: "scratch.md").path))
        #expect(!(app.logEntries.contains { $0.action == .worktreeRemoveAnyway }))
    }
}
