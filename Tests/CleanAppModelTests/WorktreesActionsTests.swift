@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// PLAN §8.4 and §8.5: what Remove…, the Delete key and the group headers may do. A repo folder is never part of
/// a removal, and Remove… is disabled (with why) when the selection holds nothing that can be removed, so the
/// removal sheet never opens to say "nothing can be removed".
@Suite("Worktrees actions")
@MainActor
struct WorktreesActionsTests {
    private func mainID(_ model: WorktreesModel, _ repo: URL) throws -> WorktreeRow.ID {
        try #require(model.allRows.first { $0.worktree.isMain && CanonicalPath.same($0.url, repo) }).id
    }

    @Test func aRepoFolderIsAHeaderAndNeverRemovable() async throws {
        let (world, _, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let atlas = try mainID(model, world.repos[0])

        model.selection = [atlas]
        #expect(model.selectedRows.isEmpty, "a header is not a row")
        #expect(model.selectedRepos.map(\.id) == [atlas])
        #expect(model.isShowingDetails, "selecting the header shows the repo folder in the details panel")
        guard case .one(let shown) = model.detailsSelection else {
            Issue.record("expected the repo folder in the details panel")
            return
        }
        #expect(shown.worktree.isMain && shown.fix == .cleanDependencies)
        #expect(shown.explanation == WorktreeStatusText.repoFolderSentence)
        #expect(!model.canRemoveSelection)
        #expect(model.removeDisabledReason == "This is the repo itself. Bonsai only removes extra worktrees; "
            + "use Clean dependencies to free space here.")

        // Remove…, the Delete key and the selection bar all go through removeSelection: nothing opens.
        await model.removeSelection()
        #expect(!model.isShowingRemovalSheet && model.confirmation == nil)
        await model.beginRemoval([atlas])
        #expect(!model.isShowingRemovalSheet, "not even when asked for by id")
        #expect(model.selectionText == "1 selected · nothing to remove")
    }

    @Test func removeIsDisabledForASelectionOfOnlyNonRemovableRows() async throws {
        let (world, _, model) = try await scannedDemoWorld()
        defer { world.remove() }
        model.selection = model.ids([try world.url("atlas-wip"), try world.url("cobalt-py"), try world.url("beacon-gone")])
        #expect(model.selectedRows.count == 3)
        #expect(model.removableSelection.isEmpty)
        #expect(!model.canRemoveSelection)
        #expect(model.removeDisabledReason == "None of the selected worktrees can be removed. Their details say why.")
        await model.removeSelection()
        #expect(!model.isShowingRemovalSheet)

        model.selection = model.ids([try world.url("atlas-wip")])
        #expect(model.removeDisabledReason?.hasPrefix("It can't be removed: 2 files have changes") == true,
                "\(model.removeDisabledReason ?? "")")
        model.selection = []
        #expect(model.removeDisabledReason == "Select the worktrees to remove.")
    }

    /// The Delete key opens the confirmation for what is selected and removes nothing by itself; the repo folder
    /// selected with them is left out of the sheet entirely.
    @Test func theDeleteKeyGoesThroughTheConfirmation() async throws {
        let (world, app, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let archive = try world.url("atlas-archive")
        let wip = try world.url("atlas-wip")
        model.selection = model.ids([archive, wip]).union([try mainID(model, world.repos[0])])
        #expect(model.canRemoveSelection)
        #expect(model.removeDisabledReason == nil)
        #expect(model.selectionText?.hasPrefix("3 selected (1 can be removed) · ") == true, "\(model.selectionText ?? "")")

        await model.removeSelection()
        #expect(model.isShowingRemovalSheet)
        let confirmation = try #require(model.confirmation)
        #expect(confirmation.allowed.map(\.worktree.url.lastPathComponent) == ["atlas-archive"])
        #expect(confirmation.blocked.map(\.worktree.url.lastPathComponent) == ["atlas-wip"])
        #expect(!confirmation.items.contains { $0.worktree.isMain })
        #expect(FileManager.default.fileExists(atPath: archive.path), "nothing removed before the confirmation")
        #expect(app.logEntries.isEmpty)
        model.dismissRemoval()
        #expect(!model.isShowingRemovalSheet)
    }

    @Test func removeAllOnAHeaderTakesTheGroupsRemovableWorktrees() async throws {
        let (world, _, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let beacon = try #require(model.groups.first { $0.name == "beacon" })
        #expect(beacon.removableRows.map(\.url.lastPathComponent).sorted() == ["beacon-env", "beacon-spike"])

        await model.removeAll(in: beacon)
        let confirmation = try #require(model.confirmation)
        #expect(Set(confirmation.allowed.map(\.worktree.url.lastPathComponent)) == ["beacon-env", "beacon-spike"])
        #expect(confirmation.blocked.isEmpty, "only what can go")
        model.dismissRemoval()

        // Clean dependencies on the header looks at the repo folder alone.
        let atlas = try #require(model.groups.first { $0.name == "atlas" })
        await model.cleanDependencies(of: atlas)
        let clean = try #require(model.lightCleanConfirmation)
        #expect(clean.items.map(\.worktree.isMain) == [true])
        model.dismissLightClean()
    }
}
