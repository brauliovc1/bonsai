import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Worktrees model")
@MainActor
struct WorktreesModelTests {
    /// PLAN §8.4: "Can remove" (what a removal by hand accepts), "Needs attention" (the orange chips), "All";
    /// a repo folder is never a row.
    @Test func filtersCountsAndSearch() async throws {
        let (world, _, model) = try await scannedDemoWorld()
        defer { world.remove() }
        #expect(model.allRows.count == world.items.count + world.repos.count)
        #expect(model.linkedRows.count == world.items.count)
        #expect(WorktreesModel(app: model.app).filter == .canRemove, "the screen opens on Can remove")
        model.filter = .canRemove
        func shown() -> Set<String> { Set(model.rows.map(\.url.lastPathComponent)) }

        #expect(shown() == [
            "atlas-archive", "atlas-review", "tidy-otter", "beacon-spike", "beacon-env", "cobalt-web", "cobalt-swift",
        ])
        #expect(model.rows.allSatisfy { $0.canRemove })
        model.filter = .needsAttention
        #expect(shown() == ["atlas-wip", "beacon-bisect", "beacon-env", "cobalt-py"])
        #expect(model.rows.allSatisfy { $0.chip.tone == .orange })
        model.filter = .all
        #expect(model.rows.count == world.items.count)
        #expect(!model.rows.contains { $0.worktree.isMain }, "a repo folder is its group's header, never a row")
        #expect(WorktreesModel.Filter.allCases.map { model.count($0) } == [7, 4, 11])
        #expect(WorktreesModel.Filter.allCases.map { model.title($0) } == ["Can remove · 7", "Needs attention · 4", "All · 11"])
        // The Overview's Worktrees part counts exactly the "Can remove" rows.
        #expect(model.app.removableAssessments.count == model.count(.canRemove))

        model.searchText = "  BEACON "
        #expect(model.rows.count == 4, "repo name, case-insensitive, trimmed")
        #expect(model.rows.allSatisfy { $0.repoName == "beacon" })
        #expect(WorktreesModel.Filter.allCases.map { model.count($0) } == [2, 2, 4], "counts follow the search")
        model.searchText = "claude/tidy"
        #expect(model.rows.map(\.url.lastPathComponent) == ["tidy-otter"], "branch")
        model.searchText = "detached"
        #expect(model.rows.map(\.url.lastPathComponent) == ["beacon-bisect"], "detached HEAD's branch text")
        model.searchText = "nothing matches this"
        #expect(model.rows.isEmpty && model.groups.isEmpty)

        model.searchText = "archive"
        model.filter = .needsAttention
        model.showRemovable()
        #expect(model.filter == .canRemove && model.searchText.isEmpty, "the Overview's card opens on what it counted")
    }

    /// Sorting applies inside each repo group (biggest first unless set); groups stay in repo order.
    @Test func sortingInsideGroups() async throws {
        let (world, _, model) = try await scannedDemoWorld()
        defer { world.remove() }
        model.filter = .all
        func linked(_ repo: String) -> [WorktreeRow] {
            let group = model.groups.first { $0.name == repo }
            #expect(group?.main?.worktree.isMain == true, "\(repo): the header is the repo folder")
            #expect(group?.rows.contains { $0.worktree.isMain } == false)
            return group?.rows ?? []
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

        model.filter = .all
        let confirmation = await model.prepareRemoval(model.ids([archive, otter, env, wip, swift, python, atlas]))
        #expect(confirmation.items.count == 6, "the repo folder is never part of a removal, not even as a blocked item")
        #expect(Set(confirmation.allowed.map(\.worktree.url.lastPathComponent)) == [
            "atlas-archive", "tidy-otter", "beacon-env", "cobalt-swift",
        ])
        #expect(Set(confirmation.blocked.map(\.worktree.url.lastPathComponent)) == ["atlas-wip", "cobalt-py"])
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
        #expect(row.statusLabel == "IN USE", "the CLI's words are kept")
        #expect(row.chip == StatusWords("Open in zsh", .blue, symbol: "macwindow"))
        #expect(row.explanation.contains("zsh (pid 4242)"))
        #expect(row.reasonsHelp.contains("zsh (pid 4242)"))
        #expect(row.fix == .refresh)
        #expect(!row.canRemove && !row.needsAttention)
    }
}
