import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Worktrees grouped by repo")
@MainActor
struct WorktreeGroupsTests {
    @Test func groupHeadersShowFolderRemoteCountAndSize() async throws {
        let (world, _, model) = try await scannedDemoWorld()
        defer { world.remove() }
        #expect(model.groups.map(\.name) == ["atlas", "beacon", "cobalt"])
        #expect(model.groups.map(\.rows.count) == [5, 5, 4])
        #expect(model.rows.count == model.allRows.count, "rows are the groups' rows, in group order")

        let atlas = try #require(model.groups.first)
        let repo = world.repos[0]
        #expect(atlas.repoPath == Worktree.standardize(repo.path))
        #expect(atlas.folderText == atlas.repoPath, "outside the home folder: the path as it is")
        #expect(atlas.countText == "5 worktrees")
        #expect(atlas.remotes.map(\.name) == ["origin"])
        #expect(atlas.remotes.first?.url.hasSuffix("/remotes/atlas.git") == true)
        #expect(atlas.remoteText?.hasSuffix("/remotes/atlas.git") == true)
        #expect(atlas.totalBytes == atlas.rows.compactMap(\.sizeBytes).reduce(0, +))
        #expect((atlas.totalBytes ?? 0) > 0)
        #expect(atlas.rows.first?.worktree.isMain == true)

        let beacon = try #require(model.groups.first { $0.name == "beacon" })
        let gone = try #require(beacon.rows.first { $0.isMissingFolder })
        #expect(gone.sizeBytes == nil)
        #expect(beacon.totalBytes == beacon.rows.compactMap(\.sizeBytes).reduce(0, +), "unknown sizes are left out")
    }

    @Test func filtersAndSearchWorkInsideGroups() async throws {
        let (world, _, model) = try await scannedDemoWorld()
        defer { world.remove() }

        model.statusFilter = .autoReady
        #expect(model.groups.map(\.name) == ["atlas"], "a repo with no shown row has no group")
        #expect(model.groups.first?.rows.map(\.url.lastPathComponent) == ["atlas-archive"])
        #expect(model.groups.first?.countText == "1 of 5 worktrees")
        #expect(model.groups.first?.totalBytes == model.groups.first?.rows.first?.sizeBytes)
        model.clearFilters()

        model.searchText = "remotes/beacon"
        #expect(model.groups.map(\.name) == ["beacon"], "the remote")
        #expect(model.rows.count == 5)
        model.searchText = "notes/review.md"
        #expect(model.rows.map(\.url.lastPathComponent) == ["atlas-review"], "the last commit's message")
        model.searchText = "add NOTES/otter"
        #expect(model.rows.map(\.url.lastPathComponent) == ["tidy-otter"], "case-insensitive")
        let folder = try #require(model.row(try world.url("cobalt-swift"))?.folderText)
        model.searchText = String(folder.suffix(18))
        #expect(model.rows.map(\.url.lastPathComponent) == ["cobalt-swift"], "the folder")
    }

    @Test func lastCommitAndFolderColumns() async throws {
        let (world, _, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let archive = try #require(model.row(try world.url("atlas-archive")))
        #expect(archive.lastCommitText == "Add notes/archive.md")
        #expect(archive.lastCommitAgoText == "45d ago")
        #expect(archive.lastCommitHelp.hasPrefix("Add notes/archive.md\n\nFixture · "))
        #expect(archive.lastCommitHelp.hasSuffix(String(archive.worktree.head?.prefix(8) ?? "?")))
        let bisect = try #require(model.row(try world.url("beacon-bisect")))
        #expect(bisect.worktree.isDetached)
        #expect(bisect.lastCommitText == "Add probe.md")
        #expect(bisect.lastCommit?.sha == bisect.worktree.head)
        let gone = try #require(model.row(try world.url("beacon-gone")))
        #expect(gone.lastCommitText == "Add notes/gone.md", "git's record still names the commit")

        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        let worktree = Worktree(path: "/Users/me/Documents/GitHub/Nexus-a13", repoPath: "/Users/me/Documents/GitHub/Nexus",
                                head: "abc", branch: "a13", isMain: false, kind: .sibling)
        let safety = SafetyReport(blockers: [], notes: [], autoBlockers: [])
        let row = WorktreeRow(assessment: WorktreeAssessment(worktree: worktree, idle: .idle(days: 3), safety: safety),
                              scanOrder: 0, home: home)
        #expect(row.folderText == "~/Documents/GitHub/Nexus-a13")
        #expect(row.repoFolderText == "~/Documents/GitHub/Nexus")
        #expect(row.lastCommitText == "–" && row.lastCommitAgoText.isEmpty)

        let now = Date(timeIntervalSince1970: 1_000_000_000)
        #expect(DisplayText.ago(now.addingTimeInterval(-30), now: now) == "just now")
        #expect(DisplayText.ago(now.addingTimeInterval(-125), now: now) == "2m ago")
        #expect(DisplayText.ago(now.addingTimeInterval(-5 * 3_600), now: now) == "5h ago")
        #expect(DisplayText.ago(now.addingTimeInterval(-3 * 86_400 - 60), now: now) == "3d ago")
        #expect(DisplayText.ago(now.addingTimeInterval(-800 * 86_400), now: now) == "2y ago")
        #expect(DisplayText.ago(now.addingTimeInterval(7_200), now: now) == "in the future")
    }

    @Test func selectionCollapseAndTheRemovalSheetGetTheRightRows() async throws {
        let (world, _, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let archive = try world.url("atlas-archive")
        let env = try world.url("beacon-env")
        let web = try world.url("cobalt-web")

        #expect(!model.isShowingDetails)
        model.selection = model.ids([archive])
        #expect(model.isShowingDetails, "selecting one row opens the details panel")
        guard case .one(let shown) = model.detailsSelection else {
            Issue.record("expected one row")
            return
        }
        #expect(CanonicalPath.same(shown.url, archive))
        model.isShowingDetails = false
        model.selection = model.ids([archive, env, web])
        #expect(!model.isShowingDetails, "several rows don't reopen it")
        guard case .several(let summary) = model.detailsSelection else {
            Issue.record("expected a summary")
            return
        }
        #expect(summary.count == 3 && summary.repoCount == 3 && summary.removableCount == 3)
        #expect(summary.title == "3 worktrees selected in 3 repos")

        let beacon = Worktree.standardize(world.repos[1].path)
        model.setExpanded(false, repo: beacon)
        #expect(!model.isExpanded(beacon))
        #expect(model.selection == model.ids([archive, web]), "collapsing deselects the hidden rows")
        #expect(model.rows.count == model.allRows.count, "collapsed rows still count as shown")
        #expect(model.tableItems.count == 3 + 5 + 4, "three headers, atlas's and cobalt's rows, none of beacon's")
        #expect(model.tableItems.contains(.group(try #require(model.groups.first { $0.repoPath == beacon }))))
        #expect(!model.tableItems.contains { $0.row?.worktree.repoPath == beacon })
        let confirmation = await model.prepareRemoval(model.selection)
        #expect(Set(confirmation.allowed.map(\.worktree.url.lastPathComponent)) == ["atlas-archive", "cobalt-web"])
        #expect(confirmation.blocked.isEmpty)
        model.toggleExpanded(beacon)
        #expect(model.isExpanded(beacon))
        #expect(model.tableItems.count == 3 + model.allRows.count)
        #expect(model.tableItems.first == .group(try #require(model.groups.first)), "a header comes first")
    }

    @Test func theTableSortOrderMapsToTheModels() {
        let size = KeyPathComparator(\WorktreeRow.sizeSortKey, order: .reverse)
        let table = WorktreeTableItem.tableSortOrder([size])
        #expect(table == [KeyPathComparator(\WorktreeTableItem.sizeSortKey, order: .reverse)])
        #expect(WorktreeTableItem.rowSortOrder(table) == [size])
        #expect(WorktreeTableItem.tableSortOrder([KeyPathComparator(\WorktreeRow.repoName)])
            == [KeyPathComparator(\WorktreeTableItem.nameSortKey)], "the default sort shows on the first column")
        #expect(WorktreeTableItem.rowSortOrder([KeyPathComparator(\WorktreeTableItem.nameSortKey, order: .reverse)])
            == [KeyPathComparator(\WorktreeRow.branchText, order: .reverse)])
        for (item, row) in [
            (KeyPathComparator(\WorktreeTableItem.lastCommitSortKey), KeyPathComparator(\WorktreeRow.lastCommitSortKey)),
        ] {
            #expect(WorktreeTableItem.rowSortOrder([item]) == [row])
        }
        #expect(WorktreeTableItem.rowSortOrder([KeyPathComparator(\WorktreeTableItem.folderText)])
            == [KeyPathComparator(\WorktreeRow.folderText)])
        #expect(WorktreeTableItem.tableSortOrder([KeyPathComparator(\WorktreeRow.scanOrder)]).isEmpty)
    }

    @Test func theTestModeBannerShowsOnlyWithTheVariable() throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let set = AppModel(environment: fixture.environment(scanRoots: [fixture.scanRoot]), git: fixture.git)
        #expect(set.testModeText == "Test mode: scanning only \(fixture.scanRoot.path) (CLEAN_CLAUDE_SCAN_ROOTS)")
        let unset = AppModel(environment: fixture.environment(), git: fixture.git)
        #expect(unset.testModeText == nil)

        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        let live = CleanEnvironment.make(homeDirectory: home, variables: ["CLEAN_CLAUDE_SCAN_ROOTS": "~/demo:/tmp/w"],
                                         tools: ToolPaths())
        #expect(AppModel(environment: live, git: fixture.git).testModeText
            == "Test mode: scanning only ~/demo, /tmp/w (CLEAN_CLAUDE_SCAN_ROOTS)")
        let empty = CleanEnvironment.make(homeDirectory: home, variables: ["CLEAN_CLAUDE_SCAN_ROOTS": ""], tools: ToolPaths())
        #expect(AppModel(environment: empty, git: fixture.git).testModeText == nil)
    }
}
