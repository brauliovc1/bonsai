@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// PLAN §8.5: after a cleanup that touched a checkout its size is measured again at once, just that checkout,
/// the row showing "Measuring…" meanwhile; a removed worktree leaves its group (and the group's size) at once.
@Suite("Sizes after a cleanup")
@MainActor
struct SizesAfterCleanupTests {
    @Test func aLightCleanedCheckoutsRowDropsWithoutAFullRescan() async throws {
        let (world, app, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let web = try world.url("cobalt-web")
        let before = try #require(model.row(web)?.sizeBytes)
        #expect(before > 19 * 1024 * 1024)
        let cobalt = try #require(model.groups.first { $0.name == "cobalt" })
        let groupBefore = try #require(cobalt.worktreeBytes)
        let scans = app.scanCount

        // While it is measured again the row says so.
        let worktree = try #require(model.row(web)?.worktree)
        let measuring = Task { await app.remeasureSizes(of: [worktree]) }
        for _ in 0..<200 where !app.measuringSizes.contains(worktree.path) { await Task.yield() }
        #expect(model.row(web)?.isMeasuringSize == true)
        #expect(model.groups.first { $0.name == "cobalt" }?.rows.first { CanonicalPath.same($0.url, web) }?.isMeasuringSize == true)
        await measuring.value
        #expect(model.row(web)?.isMeasuringSize == false)

        let confirmation = await model.prepareLightClean(model.ids([web]))
        let report = await model.confirmLightClean(confirmation)
        #expect(report.deletedCount == 1)
        let after = try #require(model.row(web)?.sizeBytes)
        #expect(after < 1024 * 1024, "20 MB of node_modules gone from the row: \(after)")
        #expect(app.scanCount == scans, "no full rescan")
        #expect(app.measuringSizes.isEmpty)
        #expect(app.scan?.sizes[worktree.path] == after, "the scan's own sizes too (the removal sheet reads them)")
        let groupAfter = try #require(model.groups.first { $0.name == "cobalt" }?.worktreeBytes)
        #expect(groupBefore - groupAfter == before - after)
        #expect(app.removableAssessments.first { $0.worktree.path == worktree.path }?.estimatedBytes == after,
                "the Overview's total follows")
    }

    /// A repo folder measured again leaves out the worktrees inside it, as the scan does.
    @Test func aRepoFolderMeasuredAgainLeavesItsWorktreesOut() async throws {
        let (world, app, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let atlas = try #require(model.allRows.first { $0.worktree.isMain && CanonicalPath.same($0.url, world.repos[0]) })
        let scanned = try #require(atlas.sizeBytes)
        // tidy-otter lives inside atlas and grows by 3 MiB; measured together, atlas leaves out its new size.
        let otter = try #require(model.row(try world.url("tidy-otter")))
        try AgedRepos(fixture: world.fixture).blob(in: otter.url, "build/out.bin", megabytes: 3)
        await app.remeasureSizes(of: [atlas.worktree, otter.worktree])
        let again = try #require(model.allRows.first { $0.id == atlas.id }?.sizeBytes)
        #expect(abs(again - scanned) <= 64 * 1024, "\(scanned) then \(again)")
        #expect((model.row(otter.url)?.sizeBytes ?? 0) >= 3 * 1024 * 1024)
        await app.remeasureSizes(of: [otter.worktree, atlas.worktree])
        #expect(abs((model.allRows.first { $0.id == atlas.id }?.sizeBytes ?? 0) - scanned) <= 64 * 1024, "in any order")
    }

    @Test func removingAWorktreeUpdatesItsGroupAtOnce() async throws {
        let (world, app, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let archive = try world.url("atlas-archive")
        let row = try #require(model.row(archive))
        let size = try #require(row.sizeBytes)
        let atlas = try #require(model.groups.first { $0.name == "atlas" })
        let before = try #require(atlas.worktreeBytes)
        let scans = app.scanCount

        // What the removal flow does after Remover removed it, before the rescan.
        await app.cleanupFinished(rescanWorktrees: false, removed: [row.worktree])
        let header = try #require(model.groups.first { $0.name == "atlas" })
        #expect(header.worktreeBytes == before - size)
        #expect(header.countText == "3 worktrees")
        #expect(!header.rows.contains { $0.id == row.id })
        #expect(app.scanCount == scans)

        // And the real flow: confirmed, removed by Remover, gone from the group, then rescanned.
        let (other, otherApp, otherModel) = try await scannedDemoWorld()
        defer { other.remove() }
        let review = try other.url("atlas-review")
        let reviewSize = try #require(otherModel.row(review)?.sizeBytes)
        let groupBefore = try #require(otherModel.groups.first { $0.name == "atlas" }?.worktreeBytes)
        let confirmation = await otherModel.prepareRemoval(otherModel.ids([review]))
        let outcomes = await otherModel.confirmRemoval(confirmation)
        #expect(outcomes.map(\.removed) == [true])
        #expect(otherModel.row(review) == nil)
        let groupAfter = try #require(otherModel.groups.first { $0.name == "atlas" }?.worktreeBytes)
        #expect(groupAfter <= groupBefore - reviewSize + 64 * 1024 && groupAfter < groupBefore)
        #expect(otherApp.logEntries.count == 1)
    }
}
