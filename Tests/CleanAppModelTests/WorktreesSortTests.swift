@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// "Sort: Size / Last activity / Name" and "Group by repo" (P12b addition): groups and rows follow the same key,
/// the flat list sorts across repos, unknown sizes go last, and the selection doesn't care about the order.
@Suite("Worktrees sort")
@MainActor
struct WorktreesSortTests {
    /// Known values in the order asked for, then every unknown one.
    private func ordered<T: Comparable>(_ values: [T?], descending: Bool) -> Bool {
        let known = values.prefix { $0 != nil }.compactMap { $0 }
        let rest = values.dropFirst(known.count)
        let sorted = zip(known, known.dropFirst()).allSatisfy { descending ? $0 >= $1 : $0 <= $1 }
        return sorted && rest.allSatisfy { $0 == nil }
    }

    private func group(_ model: WorktreesModel, _ name: String) -> [WorktreeRow] {
        model.groups.first { $0.name == name }?.rows ?? []
    }

    @Test func eachKeyOrdersGroupsAndRows() async throws {
        let (world, _, model) = try await scannedDemoWorld()
        defer { world.remove() }
        #expect(model.sortKey == .size && model.groupsByRepo, "Size and grouped when the screen opens")

        // Size: groups by their shown worktrees' total, rows largest first, unknown last.
        #expect(model.groups.first?.name == "cobalt", "20 MB of node_modules in cobalt-web")
        #expect(ordered(model.groups.map(WorktreesModel.shownSize), descending: true))
        for group in model.groups {
            #expect(ordered(group.rows.map(\.sizeBytes), descending: true), "\(group.name)")
            // The repo folder isn't removable, so its size (non-zero here) doesn't count.
            let sizes = group.rows.compactMap(\.sizeBytes)
            #expect((group.main?.sizeBytes ?? 0) > 0)
            #expect(WorktreesModel.shownSize(group) == (sizes.isEmpty ? nil : sizes.reduce(0, +)), "\(group.name)")
        }
        #expect(group(model, "cobalt").first?.url.lastPathComponent == "cobalt-web")
        #expect(group(model, "beacon").last?.isMissingFolder == true, "no size: last")

        // Last activity: oldest first; a group by its oldest worktree; unknown last.
        model.sortKey = .activity
        #expect(ordered(model.groups.map { $0.rows.compactMap(\.idleDays).max() }, descending: true))
        for group in model.groups {
            #expect(ordered(group.rows.map(\.idleDays), descending: true), "\(group.name)")
        }
        #expect(group(model, "atlas").compactMap(\.idleDays) == [45, 45, 10, 3])
        #expect(group(model, "beacon").last?.isMissingFolder == true, "activity unknown: last")

        // Name: repos, then branches, in Finder's order.
        model.sortKey = .name
        #expect(model.groups.map(\.name) == ["atlas", "beacon", "cobalt"])
        #expect(group(model, "cobalt").map(\.branchText) == ["py", "swift", "web"])
        #expect(model.rows == model.groups.flatMap(\.rows), "the list order is the groups' order")
    }

    @Test func theFlatListSortsAcrossRepos() async throws {
        let (world, _, model) = try await scannedDemoWorld()
        defer { world.remove() }
        model.groupsByRepo = false
        let rows = model.rows
        #expect(rows == model.flatRows && rows.count == model.linkedRows.count)
        #expect(ordered(rows.map(\.sizeBytes), descending: true), "largest first across every repo")
        #expect(rows.first?.url.lastPathComponent == "cobalt-web")
        #expect(rows.last?.isMissingFolder == true)
        let repos = rows.map(\.repoName)
        #expect(Set(repos) == ["atlas", "beacon", "cobalt"])
        #expect(zip(repos, repos.dropFirst()).filter { $0 != $1 }.count > 2, "repos interleave by size")

        model.sortKey = .name
        #expect(model.rows.map { "\($0.repoName)/\($0.branchText)" }.prefix(2) == ["atlas/archive", "atlas/claude/tidy-otter"])
        model.sortKey = .activity
        #expect(ordered(model.rows.map(\.idleDays), descending: true))
        // Filter and search still apply.
        model.filter = .canRemove
        #expect(model.rows.allSatisfy(\.canRemove) && model.rows.count == model.count(.canRemove))
        model.searchText = "beacon"
        #expect(Set(model.rows.map(\.repoName)) == ["beacon"])
    }

    /// A size being measured again, or never measured, sorts last, never first: in its group, in the flat list,
    /// and in the group's total.
    @Test func unmeasuredSizesGoLast() async throws {
        let (world, app, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let web = try world.url("cobalt-web")
        let cobaltBefore = try #require(model.groups.first { $0.name == "cobalt" })
        app.measuringSizes.insert(try #require(model.row(web)).path)
        #expect(try #require(model.row(web)).isMeasuringSize)

        #expect(group(model, "cobalt").last?.url.lastPathComponent == "cobalt-web", "Measuring… goes last")
        let cobalt = try #require(model.groups.first { $0.name == "cobalt" })
        #expect(WorktreesModel.shownSize(cobalt)! < WorktreesModel.shownSize(cobaltBefore)!, "not counted while measured")
        model.groupsByRepo = false
        let flat = model.rows.map(\.url.lastPathComponent)
        #expect(flat.firstIndex(of: "cobalt-web")! > flat.firstIndex(of: "atlas-archive")!)
        #expect(flat.suffix(2).contains("cobalt-web"), "with the other unknown size, at the end")

        // A group with no known size goes last.
        model.groupsByRepo = true
        for row in model.rows where row.repoName == "atlas" { app.measuringSizes.insert(row.path) }
        #expect(model.groups.last?.name == "atlas")
        #expect(WorktreesModel.shownSize(try #require(model.groups.last)) == nil)
    }

    @Test func theSelectionSurvivesAResort() async throws {
        let (world, _, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let picked = model.ids([try world.url("atlas-archive"), try world.url("cobalt-web")])
        model.selection = picked
        for key in WorktreesModel.SortKey.allCases {
            for grouped in [true, false] {
                model.sortKey = key
                model.groupsByRepo = grouped
                #expect(model.selection == picked, "\(key) \(grouped)")
                #expect(Set(model.selectedRows.map(\.id)) == picked, "\(key) \(grouped)")
                guard case .several(let summary) = model.detailsSelection else {
                    Issue.record("details lost the selection: \(key) \(grouped)")
                    continue
                }
                #expect(summary.count == 2)
            }
        }
        model.selection = model.ids([try world.url("beacon-env")])
        model.sortKey = .name
        model.groupsByRepo = false
        guard case .one(let row) = model.detailsSelection else {
            Issue.record("details lost the row")
            return
        }
        #expect(row.url.lastPathComponent == "beacon-env")
    }
}
