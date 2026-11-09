@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// Review items 3 and 6: prune clears only the records the person was shown.
@Suite("Prune only what was shown")
@MainActor
struct PruneScopeTests {
    /// 3, review experiment E2: only repos with a missing folder among the shown rows are pruned.
    @Test func onlyShownReposArePruned() async throws {
        let world = try await DemoWorld.build()
        defer { world.remove() }
        let web = try world.url("cobalt-web")
        try world.fixture.deleteFolder(web)
        let app = makeApp(world.fixture)
        await app.refresh()
        let model = showingAll(WorktreesModel(app: app))
        #expect(model.missingFolderRows.count == 2)

        model.searchText = "atlas"
        #expect(model.missingFolderRows.isEmpty)
        #expect(await model.preparePrune().repos.isEmpty)

        model.searchText = "beacon"
        let plan = await model.preparePrune()
        #expect(plan.repos.map(\.repoName) == ["beacon"])
        let entry = try #require(plan.repos.first?.entries.first)
        #expect(plan.entryCount == 1)
        #expect(entry.branch == "gone")
        #expect(PrunePlan.describe(entry).contains("beacon-gone"))

        let outcomes = await model.prune(plan)
        #expect(outcomes.map(\.repoName) == ["beacon"])
        #expect(outcomes.first?.pruned.count == 1)
        model.searchText = ""
        #expect(model.row(try world.url("beacon-gone")) == nil)
        #expect(model.row(web)?.isMissingFolder == true, "cobalt's missing folder wasn't shown, so it stays")
        #expect(app.logEntries.count == 1)
    }

    /// 3: a folder that went missing after the plan was shown stops that repo's prune.
    @Test func aFolderMissingSinceThePlanStopsThePrune() async throws {
        let (world, app, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let plan = await model.preparePrune()
        #expect(plan.entryCount == 1)
        let env = try world.url("beacon-env")
        try world.fixture.deleteFolder(env)

        let outcome = try #require(await model.prune(plan).first)
        #expect(outcome.pruned.isEmpty)
        #expect(outcome.refusals.first?.contains("changed since they were shown") == true, "\(outcome.refusals)")
        #expect(outcome.refusals.contains { $0.contains("beacon-env") })
        #expect(app.logEntries.isEmpty)
        #expect(model.row(try world.url("beacon-gone"))?.isMissingFolder == true)
        #expect(model.row(env)?.isMissingFolder == true)
    }

    /// 6: when another cleanup is running, the result says so instead of being empty.
    @Test func pruneWhileAnotherCleanupRunsSaysSo() async throws {
        let (world, app, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let plan = await model.preparePrune()
        let outcomes = await app.cleaningUp { await model.prune(plan) } ?? []

        #expect(outcomes.count == 1)
        #expect(model.pruneOutcomes?.isEmpty == false)
        #expect(model.pruneOutcomes?.first?.summary.contains("another cleanup is still running") == true)
        #expect(model.row(try world.url("beacon-gone"))?.isMissingFolder == true)
        #expect(app.logEntries.isEmpty)
    }
}
