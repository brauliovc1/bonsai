@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// Review items 1, 2, 4 and 5: nothing is removed that the sheet didn't show.
@Suite("Removal matches what was confirmed")
@MainActor
struct ConfirmedStateTests {
    /// 1(a): the sheet looks again, so a file written after the scan is listed.
    @Test func theSheetIsBuiltFromAFreshLook() async throws {
        let (world, _, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let archive = try world.url("atlas-archive")
        try world.fixture.write("SECRET=1\n", to: ".env", in: archive)

        let confirmation = await model.prepareRemoval(model.ids([archive]))
        let item = try #require(confirmation.allowed.first)
        #expect(item.ignoredUserFiles == [".env"])
        #expect(model.row(archive)?.statusLabel == "AUTO-READY", "the row is still the scan's; the sheet looked again")
    }

    /// 1(b), review experiment E1: a file written after the sheet opened stops the removal.
    @Test func anIgnoredFileAddedAfterTheSheetOpenedStopsTheRemoval() async throws {
        let (world, app, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let archive = try world.url("atlas-archive")
        let confirmation = await model.prepareRemoval(model.ids([archive]))
        #expect(confirmation.allowed.first?.ignoredUserFiles == [])
        try world.fixture.write("SECRET=1\n", to: ".env", in: archive)

        let outcome = try #require(await model.confirmRemoval(confirmation).first)
        #expect(!outcome.removed)
        #expect(outcome.changedSinceConfirmed)
        #expect(outcome.error?.contains(".env") == true, "\(outcome.error ?? "")")
        #expect(FileManager.default.fileExists(atPath: archive.appending(path: ".env").path))
        #expect(app.logEntries.isEmpty)
        #expect(model.report?.changedCount == 1)
        #expect(model.report?.measuredFreedBytes == nil, "nothing was removed, so nothing was freed")
        #expect(model.report?.summary == "Nothing was removed. 1 changed since you confirmed it and was left alone; "
            + "review it again.")
        let row = try #require(model.row(archive), "rescanned: the row shows the new state")
        #expect(row.statusLabel == "SAFE")
        #expect(row.reasons.contains(.ignoredUserFiles([".env"])))
    }

    /// 1(b): counts compare exactly; one more local-only commit than confirmed stops the removal.
    @Test func anotherLocalOnlyCommitStopsTheRemoval() async throws {
        let (world, app, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let spike = try world.url("beacon-spike")
        let confirmation = await model.prepareRemoval(model.ids([spike]))
        #expect(confirmation.allowed.first?.notes.contains(.localOnlyCommits(count: 1, onBranch: true)) == true)
        try world.fixture.write("more\n", to: "more.md", in: spike)
        try await world.fixture.commitAll(in: spike, message: "More")

        let outcome = try #require(await model.confirmRemoval(confirmation).first)
        #expect(!outcome.removed)
        #expect(outcome.changedSinceConfirmed)
        #expect(outcome.error?.contains("2 commits are on no remote") == true, "\(outcome.error ?? "")")
        #expect(FileManager.default.fileExists(atPath: spike.appending(path: "more.md").path))
        #expect(app.logEntries.isEmpty)
    }

    /// 2, review experiment E3: another worktree registered at the same path is left alone.
    @Test func aDifferentWorktreeAtTheSamePathIsLeftAlone() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let repo = try await fixture.makeRepo("solo")
        let task = try await fixture.addSiblingWorktree(to: repo, name: "task")
        let app = makeApp(fixture, root: fixture.scanRoot)
        await app.refresh()
        let model = showingAll(WorktreesModel(app: app))
        let confirmation = await model.prepareRemoval(model.ids([task]))
        #expect(confirmation.allowed.first?.branchText == "task")
        try await fixture.run(["worktree", "remove", task.path], in: repo)
        try await fixture.run(["worktree", "add", "--quiet", "-b", "other", task.path], in: repo)

        let outcome = try #require(await model.confirmRemoval(confirmation).first)
        #expect(!outcome.removed)
        #expect(outcome.changedSinceConfirmed)
        #expect(outcome.error?.contains("The branch is now other (was task).") == true, "\(outcome.error ?? "")")
        #expect(try await fixture.run(["rev-parse", "--abbrev-ref", "HEAD"], in: task) == "other")
        #expect(app.logEntries.isEmpty)
        #expect(model.row(task)?.branchText == "other")
    }

    /// 4, review experiment E4: two repos list one folder (a stale record and a real worktree).
    @Test func twoReposListingOneFolderStayTwoRows() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let alpha = try await fixture.makeRepo("alpha")
        let bravo = try await fixture.makeRepo("bravo")
        let shared = fixture.scanRoot.appending(path: "shared", directoryHint: .isDirectory)
        try await fixture.addWorktree(to: alpha, at: shared, branch: "a-task")
        try FileManager.default.removeItem(at: shared)
        try await fixture.addWorktree(to: bravo, at: shared, branch: "b-task")
        let app = makeApp(fixture, root: fixture.scanRoot)
        await app.refresh()
        let model = showingAll(WorktreesModel(app: app))

        let rows = model.allRows.filter { $0.url.lastPathComponent == "shared" }
        #expect(rows.count == 2)
        #expect(Set(rows.map(\.id)).count == 2)
        let stale = try #require(rows.first { $0.repoName == "alpha" })
        let real = try #require(rows.first { $0.repoName == "bravo" })
        #expect(!stale.canRemove)
        #expect(stale.reasons.contains { reason in
            if case .staleRecord = reason { return true }
            return false
        })
        #expect(stale.statusLabel == "BLOCKED: stale record")
        #expect(stale.chip.text == "Couldn't check")
        #expect(real.canRemove)

        let confirmation = await model.prepareRemoval([real.id])
        #expect(confirmation.items.map(\.repoName) == ["bravo"])
        let outcomes = await model.confirmRemoval(confirmation)
        #expect(outcomes.map(\.removed) == [true])
        #expect(outcomes.first?.result?.entry.branch == "b-task")
    }

    /// 5: freed space is measured on every volume the removed items were on, and summed.
    @Test func freedSpaceIsSummedPerVolume() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let repo = try await fixture.makeRepo("solo")
        let one = try await fixture.addSiblingWorktree(to: repo, name: "one")
        let two = try await fixture.addSiblingWorktree(to: repo, name: "two")
        let app = makeApp(fixture, root: fixture.scanRoot)
        await app.refresh()
        let model = showingAll(WorktreesModel(app: app))
        final class Readings {
            var values = ["/volume-a": [Int64(1_000), 1_500], "/volume-b": [Int64(2_000), 2_250]]
        }
        let readings = Readings()
        model.volumeOf = { URL(fileURLWithPath: $0.lastPathComponent.hasSuffix("one") ? "/volume-a" : "/volume-b") }
        model.freeBytes = { readings.values[$0.path]?.removeFirst() }

        let outcomes = await model.confirmRemoval(await model.prepareRemoval(model.ids([one, two])))
        #expect(outcomes.map(\.removed) == [true, true])
        #expect(model.report?.measuredFreedBytes == 750, "500 on volume a plus 250 on volume b")
    }
}
