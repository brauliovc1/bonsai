import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Worktrees grouped by repo")
@MainActor
struct WorktreeGroupsTests {
    @Test func groupHeadersAreTheRepoFolders() async throws {
        let (world, _, model) = try await scannedDemoWorld()
        defer { world.remove() }
        model.filter = .all
        model.sortKey = .name  // Size is the default (P12b addition); these checks read the groups in name order.
        #expect(model.groups.map(\.name) == ["atlas", "beacon", "cobalt"])
        #expect(model.groups.map(\.rows.count) == [4, 4, 3])
        #expect(model.rows.count == model.linkedRows.count, "rows are the groups' rows, in group order")

        let atlas = try #require(model.groups.first)
        let repo = world.repos[0]
        #expect(atlas.repoPath == Worktree.standardize(repo.path))
        #expect(atlas.main?.worktree.isMain == true)
        #expect(atlas.main?.worktree.repoPath == atlas.repoPath)
        #expect(!atlas.rows.contains { $0.worktree.isMain })
        #expect(atlas.folderText == atlas.repoPath, "outside the home folder: the path as it is")
        #expect(atlas.countText == "4 worktrees")
        #expect(atlas.remotes.map(\.name) == ["origin"])
        #expect(atlas.remoteText?.hasSuffix("/remotes/atlas.git") == true)
        let linkedBytes = atlas.rows.compactMap(\.sizeBytes).reduce(0, +)
        #expect(atlas.worktreeBytes == linkedBytes && linkedBytes > 0)
        #expect(atlas.headerDetail == "repo folder \(DisplayText.bytes(atlas.main?.sizeBytes)) · 4 worktrees, "
            + "\(DisplayText.bytes(linkedBytes)) · last commit 8 weeks ago")
        #expect(atlas.removableRows.map(\.url.lastPathComponent).sorted() == ["atlas-archive", "atlas-review", "tidy-otter"])
        #expect(atlas.dependencyBytes == nil, "not measured yet")

        let beacon = try #require(model.groups.first { $0.name == "beacon" })
        let gone = try #require(beacon.rows.first { $0.isMissingFolder })
        #expect(gone.sizeBytes == nil)
        #expect(beacon.worktreeBytes == beacon.rows.compactMap(\.sizeBytes).reduce(0, +), "unknown sizes are left out")
    }

    @Test func filtersAndSearchWorkInsideGroups() async throws {
        let (world, _, model) = try await scannedDemoWorld()
        defer { world.remove() }

        model.searchText = "archive"
        #expect(model.groups.map(\.name) == ["atlas"], "a repo with no shown worktree has no group")
        #expect(model.groups.first?.rows.map(\.url.lastPathComponent) == ["atlas-archive"])
        #expect(model.groups.first?.countText == "4 worktrees", "the header counts the repo's worktrees")
        model.filter = .needsAttention
        #expect(model.groups.isEmpty)

        model.filter = .all
        model.searchText = "remotes/beacon"
        #expect(model.groups.map(\.name) == ["beacon"], "the remote")
        #expect(model.rows.count == 4)
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
        #expect(row.locationText == "~/Documents/GitHub/Nexus-a13", "beside the repo: with ~")
        #expect(row.activityText == "3 days ago")
        let otter = try #require(model.row(try world.url("tidy-otter")))
        #expect(otter.locationText == ".claude/worktrees/tidy-otter", "inside the repo: relative to it")

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
        #expect(model.groups.contains { $0.repoPath == beacon }, "a collapsed group keeps its header")
        #expect(model.rows.count == model.count(model.filter), "collapsed rows still count as shown")
        let confirmation = await model.prepareRemoval(model.selection)
        #expect(Set(confirmation.allowed.map(\.worktree.url.lastPathComponent)) == ["atlas-archive", "cobalt-web"])
        #expect(confirmation.blocked.isEmpty)
        model.toggleExpanded(beacon)
        #expect(model.isExpanded(beacon))
    }

    @Test func theTestModeBannerShowsOnlyWithTheVariable() throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let set = AppModel(environment: fixture.environment(scanRoots: [fixture.scanRoot]), git: fixture.git)
        #expect(set.testModeText == "Test mode: scanning only \(fixture.scanRoot.path) (BONSAI_SCAN_ROOTS)")
        let unset = AppModel(environment: fixture.environment(), git: fixture.git)
        #expect(unset.testModeText == nil)

        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        let live = CleanEnvironment.make(homeDirectory: home, variables: ["BONSAI_SCAN_ROOTS": "~/demo:/tmp/w"],
                                         tools: ToolPaths())
        #expect(AppModel(environment: live, git: fixture.git).testModeText
            == "Test mode: scanning only ~/demo, /tmp/w (BONSAI_SCAN_ROOTS)")
        let empty = CleanEnvironment.make(homeDirectory: home, variables: ["BONSAI_SCAN_ROOTS": ""], tools: ToolPaths())
        #expect(AppModel(environment: empty, git: fixture.git).testModeText == nil)
    }
}
