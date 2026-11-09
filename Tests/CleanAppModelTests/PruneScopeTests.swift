@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// Review items 3 and 6: prune clears only the records the sheet showed. P12 review item 7: the sheet covers every
/// missing-folder record, whatever the filter shows (missing folders are grey, never on the default filters).
@Suite("Prune only what was shown")
@MainActor
struct PruneScopeTests {
    @Test func everyMissingFolderIsInThePlanWhateverTheFilterShows() async throws {
        let world = try await DemoWorld.build()
        defer { world.remove() }
        let web = try world.url("cobalt-web")
        try world.fixture.deleteFolder(web)
        let app = makeApp(world.fixture)
        await app.refresh()
        let model = WorktreesModel(app: app)
        #expect(model.filter == .canRemove)
        #expect(!model.rows.contains { $0.isMissingFolder }, "the default filter shows none of them")
        #expect(model.missingFolderRows.count == 2)
        #expect(model.pruneDisabledReason == nil, "Prune missing folders… is enabled on Can remove")
        model.filter = .needsAttention
        model.searchText = "atlas"
        #expect(model.missingFolderRows.count == 2 && model.pruneDisabledReason == nil, "and with any filter or search")

        let plan = await model.preparePrune()
        #expect(plan.repos.map(\.repoName).sorted() == ["beacon", "cobalt"])
        #expect(plan.entryCount == 2, "the sheet lists every one before anything is pruned")
        let entry = try #require(plan.repos.first { $0.repoName == "beacon" }?.entries.first)
        #expect(entry.branch == "gone")
        #expect(PrunePlan.describe(entry).contains("beacon-gone"))

        let outcomes = await model.prune(plan)
        #expect(outcomes.map(\.repoName).sorted() == ["beacon", "cobalt"])
        #expect(outcomes.allSatisfy { $0.pruned.count == 1 })
        #expect(model.missingFolderRows.isEmpty)
        #expect(app.logEntries.count == 2)
        #expect(model.pruneDisabledReason == "No worktree's folder is missing, so there is nothing to prune.")
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
