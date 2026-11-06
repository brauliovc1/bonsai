@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// Wave 4: light clean on a row whose folder became another repo's worktree.
@Suite("Light clean through the model: whose folder it is")
@MainActor
struct LightCleanIdentityModelTests {
    private struct World {
        let fixture: GitFixture
        let alpha: URL
        let bravo: URL
        let shared: URL
        let app: AppModel
        let model: WorktreesModel
        let alphaRow: WorktreeRow
    }

    /// alpha's worktree `shared` (alpha ignores node_modules iff `alphaIgnores`, bravo always does), scanned
    /// while it is alpha's.
    private func makeWorld(alphaIgnores: Bool) async throws -> World {
        let fixture = try GitFixture()
        let alpha = try await fixture.makeRepo("alpha")
        let bravo = try await fixture.makeRepo("bravo")
        for repo in [alpha, bravo] where repo == bravo || alphaIgnores {
            try fixture.write("node_modules/\n", to: ".gitignore", in: repo)
            try await fixture.commitAll(in: repo, message: "Ignore node_modules")
            try await fixture.run(["push", "--quiet", "origin", "main"], in: repo)
        }
        let shared = fixture.scanRoot.appending(path: "shared", directoryHint: .isDirectory)
        try await fixture.addWorktree(to: alpha, at: shared, branch: "a-task")
        try fixture.write("x\n", to: "node_modules/pkg/index.js", in: shared)
        let app = makeApp(fixture, root: fixture.scanRoot)
        await app.refresh()
        let model = WorktreesModel(app: app)
        let row = try #require(model.allRows.first { $0.repoName == "alpha" && $0.url.lastPathComponent == "shared" })
        return World(fixture: fixture, alpha: alpha, bravo: bravo, shared: shared, app: app, model: model, alphaRow: row)
    }

    /// After the scan: alpha's folder is deleted by hand and bravo adds a worktree at the same path.
    private func swapInBravo(_ world: World) async throws {
        try FileManager.default.removeItem(at: world.shared)
        try await world.fixture.addWorktree(to: world.bravo, at: world.shared, branch: "b-task")
        try world.fixture.write("x\n", to: "node_modules/pkg/index.js", in: world.shared)
    }

    private func bravosFolderIsIntact(_ world: World) -> Bool {
        FileManager.default.fileExists(atPath: world.shared.appending(path: "node_modules/pkg/index.js").path)
    }

    /// The review's probe: SAFE at scan time, then another repo's worktree at the path, then the sheet.
    @Test func theSheetForAStaleRecordListsNothingAndSaysWhy() async throws {
        let world = try await makeWorld(alphaIgnores: false)
        defer { world.fixture.remove() }
        #expect(!world.alphaRow.isStaleRecord, "fine at scan time")
        try await swapInBravo(world)

        let removal = await world.model.prepareRemoval([world.alphaRow.id])
        #expect(removal.items.first?.assessment.status.label == "BLOCKED: stale record", "the removal sheet knows")
        let confirmation = await world.model.prepareLightClean([world.alphaRow.id])

        let item = try #require(confirmation.items.first)
        #expect(item.candidates.isEmpty && !item.isCleanable)
        #expect(item.blocker?.contains("another repo's folder") == true, "\(item.blocker ?? "nil")")
        #expect(item.leftAloneReason == item.blocker)
        let report = await world.model.confirmLightClean(confirmation)
        #expect(report.deletedCount == 0)
        #expect(bravosFolderIsIntact(world))
        #expect(world.app.logEntries.isEmpty, "nothing logged under repo alpha")
    }

    /// The sheet was opened while the folder was alpha's; the swap happens before the confirm.
    @Test func aFolderThatBecameAnotherReposAfterTheSheetOpenedIsNotCleaned() async throws {
        let world = try await makeWorld(alphaIgnores: true)
        defer { world.fixture.remove() }
        let confirmation = await world.model.prepareLightClean([world.alphaRow.id])
        #expect(confirmation.items.first?.candidates.map(\.relativePath) == ["node_modules"])
        try await swapInBravo(world)

        let report = await world.model.confirmLightClean(confirmation)

        #expect(report.deletedCount == 0)
        let error = try #require(report.outcomes.first?.error)
        #expect(error.contains("no longer this repo's worktree"), "\(error)")
        #expect(bravosFolderIsIntact(world))
        #expect(world.app.logEntries.isEmpty)
    }

    @Test func aWorktreeWhoseHeadMovedAfterTheSheetOpenedIsNotCleaned() async throws {
        let world = try await makeWorld(alphaIgnores: true)
        defer { world.fixture.remove() }
        let confirmation = await world.model.prepareLightClean([world.alphaRow.id])
        #expect(confirmation.items.first?.isCleanable == true)

        try world.fixture.write("more\n", to: "notes.md", in: world.shared)
        try await world.fixture.commitAll(in: world.shared, message: "More")
        let report = await world.model.confirmLightClean(confirmation)

        #expect(report.deletedCount == 0)
        let error = try #require(report.outcomes.first?.error)
        #expect(error.contains("HEAD moved"), "\(error)")
        #expect(bravosFolderIsIntact(world), "the folder is still there (it is alpha's own)")
        #expect(world.app.logEntries.isEmpty)
    }
}
