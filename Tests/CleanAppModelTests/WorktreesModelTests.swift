import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Worktrees model")
@MainActor
struct WorktreesModelTests {
    @Test func filtersAndSearch() async throws {
        let (world, _, model) = try await scannedDemoWorld()
        defer { world.remove() }
        #expect(model.allRows.count == world.items.count + world.repos.count)
        #expect(model.rows.count == model.allRows.count)

        model.kindFilter = .claude
        #expect(model.rows.map(\.url.lastPathComponent) == ["tidy-otter"])
        model.kindFilter = .main
        #expect(model.rows.count == 3)
        model.kindFilter = nil

        model.statusFilter = .autoReady
        #expect(model.rows.map(\.url.lastPathComponent) == ["atlas-archive"])
        model.statusFilter = .safe
        #expect(Set(model.rows.map(\.url.lastPathComponent)) == [
            "atlas-review", "tidy-otter", "beacon-spike", "beacon-env", "cobalt-web", "cobalt-swift",
        ])
        model.statusFilter = .blocked
        #expect(model.rows.count == 7, "3 main checkouts, wip, bisect, gone, py")
        #expect(model.hasActiveFilters)
        model.clearFilters()
        #expect(!model.hasActiveFilters)

        model.minimumIdleDays = 30
        #expect(Set(model.rows.map(\.url.lastPathComponent)) == ["atlas-archive", "tidy-otter", "beacon-env"])
        model.statusFilter = .safe
        #expect(Set(model.rows.map(\.url.lastPathComponent)) == ["tidy-otter", "beacon-env"], "filters combine")
        model.clearFilters()

        model.searchText = "  BEACON "
        #expect(model.rows.count == 5, "repo name, case-insensitive, trimmed")
        #expect(model.rows.allSatisfy { $0.repoName == "beacon" })
        model.searchText = "claude/tidy"
        #expect(model.rows.map(\.url.lastPathComponent) == ["tidy-otter"], "branch")
        model.searchText = "detached"
        #expect(model.rows.map(\.url.lastPathComponent) == ["beacon-bisect"], "detached HEAD's branch text")
        model.searchText = "nothing matches this"
        #expect(model.rows.isEmpty)
    }

    /// Sorting applies inside each repo group; the main checkout stays first, groups stay in repo order.
    @Test func sortingInsideGroups() async throws {
        let (world, _, model) = try await scannedDemoWorld()
        defer { world.remove() }
        func linked(_ repo: String) -> [WorktreeRow] {
            let group = model.groups.first { $0.name == repo }
            #expect(group?.rows.first?.worktree.isMain == true, "\(repo): main checkout first")
            return Array(group?.rows.dropFirst() ?? [])
        }
        #expect(model.groups.map(\.name) == ["atlas", "beacon", "cobalt"])

        model.sortOrder = [KeyPathComparator(\WorktreeRow.sizeSortKey, order: .reverse)]
        #expect(model.groups.map(\.name) == ["atlas", "beacon", "cobalt"], "groups keep repo order")
        #expect(linked("cobalt").first?.url.lastPathComponent == "cobalt-web", "20 MB of node_modules")
        #expect(linked("beacon").last?.isMissingFolder == true, "unknown size sorts as smallest")

        model.sortOrder = [KeyPathComparator(\WorktreeRow.idleSortKey, order: .reverse)]
        let idle = linked("atlas").compactMap(\.idleDays)
        #expect(idle == [45, 45, 10, 3])

        model.sortOrder = [KeyPathComparator(\WorktreeRow.statusSortKey)]
        #expect(linked("atlas").first?.statusLabel == "AUTO-READY")
        #expect(linked("atlas").last?.tone == .blocked)

        model.sortOrder = [KeyPathComparator(\WorktreeRow.lastCommitSortKey, order: .reverse)]
        let dates = linked("beacon").map(\.lastCommitSortKey)
        #expect(dates == dates.sorted(by: >))

        model.sortOrder = [KeyPathComparator(\WorktreeRow.repoName, order: .reverse)]
        #expect(model.groups.map(\.name) == ["cobalt", "beacon", "atlas"])
        #expect(model.rows.first?.repoName == "cobalt")
        #expect(model.rows.first?.worktree.isMain == true)
        #expect(linked("cobalt").map(\.url.lastPathComponent) == ["cobalt-py", "cobalt-swift", "cobalt-web"],
                "ties keep scan order")

        model.sortOrder = [KeyPathComparator(\WorktreeRow.branchText, order: .reverse)]
        #expect(model.groups.first?.name == "cobalt", "the first column sorts groups too")
        #expect(linked("cobalt").map(\.branchText) == ["web", "swift", "py"])
    }

    @Test func confirmationListsBlockedItemsAndExcludesThem() async throws {
        let (world, _, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let archive = try world.url("atlas-archive")
        let otter = try world.url("tidy-otter")
        let env = try world.url("beacon-env")
        let wip = try world.url("atlas-wip")
        let swift = try world.url("cobalt-swift")
        let python = try world.url("cobalt-py")
        let atlas = world.repos[0]

        let confirmation = await model.prepareRemoval(model.ids([archive, otter, env, wip, swift, python, atlas]))
        #expect(confirmation.items.count == 7)
        #expect(Set(confirmation.allowed.map(\.worktree.url.lastPathComponent)) == [
            "atlas-archive", "tidy-otter", "beacon-env", "cobalt-swift",
        ])
        #expect(Set(confirmation.blocked.map(\.worktree.url.lastPathComponent)) == ["atlas-wip", "cobalt-py", "atlas"])
        #expect(confirmation.removeButtonTitle == "Remove 4 worktrees")
        #expect(RemovalConfirmation.keptLine == "Branches are kept. You can restore from Recently removed.")
        let estimate = confirmation.allowed.compactMap(\.estimatedBytes).reduce(0, +)
        #expect(confirmation.estimatedTotalBytes == estimate)
        #expect(estimate > 0)

        let blockedWip = try #require(confirmation.blocked.first { $0.worktree.url.lastPathComponent == "atlas-wip" })
        #expect(blockedWip.blockers.contains(.uncommitted(count: 2)))
        let blockedPython = try #require(confirmation.blocked.first { $0.worktree.url.lastPathComponent == "cobalt-py" })
        #expect(blockedPython.blockers.contains { if case .nestedCheckouts = $0 { true } else { false } })
        let packageClones = try #require(confirmation.allowed.first { $0.worktree.url.lastPathComponent == "cobalt-swift" })
        #expect(packageClones.notes.contains { if case .nestedClones = $0 { true } else { false } })
    }

    @Test func claudeWarningAndIgnoredFiles() async throws {
        let (world, _, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let confirmation = await model.prepareRemoval(model.ids([
            try world.url("tidy-otter"), try world.url("beacon-env"), try world.url("atlas-review"),
        ]))
        let otter = try #require(confirmation.allowed.first { $0.worktree.kind == .claude })
        // PLAN §4.1, exact copy.
        let planText = "This worktree belongs to a Claude session. Removing it deletes the session's folder, "
            + "so that session can't continue where it left off. The branch is kept."
        #expect(otter.claudeWarning == SafetyReason.claudeSessionWarning)
        #expect(otter.claudeWarning == planText)
        #expect(!otter.notes.contains(.claudeSession), "shown once, as the warning")

        let env = try #require(confirmation.allowed.first { $0.worktree.url.lastPathComponent == "beacon-env" })
        #expect(env.ignoredUserFiles == [".env"])
        #expect(env.claudeWarning == nil)
        let review = try #require(confirmation.allowed.first { $0.worktree.url.lastPathComponent == "atlas-review" })
        #expect(review.ignoredUserFiles.isEmpty)
        #expect(review.notes == [.recentlyActive(days: 10)])
    }

    @Test func rowsShowInUseWithProcessNameAndPid() {
        let worktree = Worktree(path: "/tmp/x/repo-a", repoPath: "/tmp/x/repo", head: "abc", branch: "a",
                                isMain: false, kind: .sibling)
        let process = ProcessCwdIndex.Entry(pid: 4242, command: "zsh", cwd: "/tmp/x/repo-a")
        let safety = SafetyReport(blockers: [.inUse([process])], notes: [], autoBlockers: [.inUse([process])])
        let row = WorktreeRow(assessment: WorktreeAssessment(worktree: worktree, idle: .idle(days: 40), safety: safety),
                              scanOrder: 0)
        #expect(row.statusLabel == "IN USE")
        #expect(row.badgeText == "IN USE")
        #expect(row.statusDetail == "zsh (pid 4242)")
        #expect(row.reasonsHelp.contains("zsh (pid 4242)"))
        #expect(!row.canRemove)
    }
}
