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
    }

    /// Review item 1: the new sizes don't depend on the order the paths are walked in (the app walks a Set, whose
    /// order changes from run to run). Both orders, deterministically: walking the repo folder first used to
    /// subtract its nested worktree's old size.
    @Test func newSizesDontDependOnTheOrder() {
        let main = Worktree(path: "/r", repoPath: "/r", head: "a", branch: "main", isMain: true, kind: .main)
        let nested = Worktree(path: "/r/.wt/w", repoPath: "/r", head: "b", branch: "w", isMain: false, kind: .other)
        let other = Worktree(path: "/r/.wt/x", repoPath: "/r", head: "c", branch: "x", isMain: false, kind: .other)
        let before: [String: Int64] = ["/r": 1_000, "/r/.wt/w": 100, "/r/.wt/x": 50]
        // du of /r counts both worktrees inside it: its own 1 000 + w's new 3 100 + x's 50.
        let measured: [String: Int64] = ["/r": 4_150, "/r/.wt/w": 3_100]
        let worktrees = [main, nested, other]
        for paths in [["/r", "/r/.wt/w"], ["/r/.wt/w", "/r"]] {
            let sizes = AppModel.sizes(measured: measured, paths: paths, before: before, worktrees: worktrees)
            #expect(sizes["/r"] == .some(1_000), "\(paths): \(String(describing: sizes["/r"]))")
            #expect(sizes["/r/.wt/w"] == .some(3_100))
            #expect(sizes["/r/.wt/x"] == nil, "not measured: not touched")
        }
        let gone = AppModel.sizes(measured: [:], paths: ["/r/.wt/w"], before: before, worktrees: worktrees)
        #expect(gone["/r/.wt/w"] == .some(nil), "a folder that is gone gets no size")
    }

    /// Review item 1, on real folders: a repo with a worktree inside it, both measured again after the worktree
    /// grew, in fresh fixtures (fresh paths, so the Set's order varies).
    @Test func aRepoFolderAndItsNestedWorktreeMeasuredTogether() async throws {
        var wrong: [String] = []
        for round in 0..<6 {
            let fixture = try GitFixture()
            defer { fixture.remove() }
            let aged = AgedRepos(fixture: fixture)
            let repo = try await aged.repo("r", days: 40, gitignore: "node_modules/\n.wt/\n")
            let inner = repo.appending(path: ".wt/w", directoryHint: .isDirectory)
            try await aged.git(["worktree", "add", "--quiet", "-b", "w", inner.path], in: repo, days: 40)
            try aged.blob(in: repo, "data/keep.bin", megabytes: 1)
            let app = makeApp(fixture)
            await app.refresh()
            let main = try #require(app.assessments.first { $0.worktree.isMain && CanonicalPath.same($0.worktree.url, repo) })
            let nested = try #require(app.assessments.first { CanonicalPath.same($0.worktree.url, inner) })
            let before = try #require(app.scan?.sizes[main.worktree.path])
            try aged.blob(in: inner, "build/out.bin", megabytes: 3)
            await app.remeasureSizes(of: round.isMultiple(of: 2) ? [nested.worktree, main.worktree] : [main.worktree, nested.worktree])
            let after = try #require(app.scan?.sizes[main.worktree.path])
            if abs(after - before) > 256 * 1024 { wrong.append("round \(round): \(before) -> \(after)") }
            #expect((app.scan?.sizes[nested.worktree.path] ?? 0) >= 3 * 1024 * 1024)
        }
        #expect(wrong.isEmpty, "the repo folder picked up its nested worktree's growth: \(wrong)")
    }

    /// Review item 5: from the moment a cleanup is finished, the touched rows say "Measuring…", also while the
    /// screens' observers look at them, until the new size is in.
    @Test func touchedRowsSayMeasuringBeforeTheObserversRun() async throws {
        let (world, app, model) = try await scannedDemoWorld()
        defer { world.remove() }
        let web = try world.url("cobalt-web")
        var seen: [Bool] = []
        app.whenCheckoutsChange { _ in seen.append(model.row(web)?.isMeasuringSize ?? false) }
        let report = await model.confirmLightClean(await model.prepareLightClean(model.ids([web])))
        #expect(report.deletedCount == 1)
        #expect(seen == [true], "measuring while the observers ran: \(seen)")
        #expect(model.row(web)?.isMeasuringSize == false, "and no longer once measured")
        #expect(app.measuringSizes.isEmpty)
        // Without du nothing is measured, and still nothing stays "Measuring…".
        var noDu = app.environment
        noDu.tools.du = nil
        let bare = AppModel(environment: noDu, git: world.fixture.git)
        await bare.refresh()
        await bare.cleanupFinished(rescanWorktrees: false, touched: bare.assessments.map(\.worktree))
        #expect(bare.measuringSizes.isEmpty)
    }

    /// Review item 2: a scan that measured before a light clean and ends after it doesn't bring the old size back.
    @Test func aScanRunningDuringALightCleanKeepsTheCleanedSize() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let aged = AgedRepos(fixture: fixture)
        let repo = try await aged.repo("india", days: 60, gitignore: ProjectFoldersDemo.gitignore, files: ["package-lock.json": "{}\n"])
        let sibling = fixture.scanRoot.appending(path: "india-done", directoryHint: .isDirectory)
        try await aged.git(["worktree", "add", "--quiet", "-b", "done", sibling.path], in: repo, days: 45)
        try await aged.commitAndPush(sibling, file: "notes/done.md", branch: "done", days: 45)
        try aged.blob(in: sibling, "node_modules/react/index.bin", megabytes: 4)

        // A du that, while `hold` exists, measures at once but answers only once `release` exists.
        let gate = fixture.url.appending(path: "gate", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: gate, withIntermediateDirectories: true)
        let script = fixture.url.appending(path: "gated-du")
        try Data("""
        #!/bin/sh
        G='\(gate.path)'
        if [ -e "$G/hold" ]; then
          out=$(/usr/bin/du "$@")
          touch "$G/started.$$"
          while [ ! -e "$G/release" ]; do sleep 0.05; done
          printf '%s\\n' "$out"
        else
          exec /usr/bin/du "$@"
        fi
        """.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        var environment = fixture.environment(scanRoots: [fixture.scanRoot])
        environment.tools.du = script
        let app = AppModel(environment: environment, git: fixture.git)
        await app.refresh()
        let model = showingAll(WorktreesModel(app: app))
        #expect((model.row(sibling)?.sizeBytes ?? 0) >= 4 * 1024 * 1024)
        let scans = app.scanCount

        // A scan starts and measures before the clean...
        FileManager.default.createFile(atPath: gate.appending(path: "hold").path, contents: nil)
        app.requestRefresh()
        func started() -> Int {
            ((try? FileManager.default.contentsOfDirectory(atPath: gate.path)) ?? []).filter { $0.hasPrefix("started.") }.count
        }
        #expect(await eventually { started() >= 2 }, "both of the scan's du calls measured within \(TestWait.limit)")
        try FileManager.default.removeItem(at: gate.appending(path: "hold"))

        // ... the worktree's dependencies are cleaned meanwhile ...
        let report = await model.confirmLightClean(await model.prepareLightClean(model.ids([sibling])))
        #expect(report.deletedCount == 1)
        #expect((model.row(sibling)?.sizeBytes ?? .max) < 1024 * 1024, "measured again right after the clean")

        // ... and the scan ends with the old reading: the cleaned size stays, and one more scan checks it.
        FileManager.default.createFile(atPath: gate.appending(path: "release").path, contents: nil)
        #expect(await eventually { !app.isScanning }, "the scans didn't end within \(TestWait.limit)")
        #expect(app.scanCount == scans + 2, "that scan, and the one it asked for; no more")
        #expect(app.cleanupFacts.sizes.isEmpty, "the later scan measured for itself and kept nothing")
        #expect((model.row(sibling)?.sizeBytes ?? .max) < 1024 * 1024, "\(model.row(sibling)?.sizeBytes ?? -1)")
        #expect(app.reclaimableBytes < 1024 * 1024, "the one total doesn't count the freed space again")
    }

    /// Re-check item 1: the kept size can itself be out of date (dependencies installed again after the clean, and
    /// the running scan measured that), so the scan that applies it asks for one more, which measures afresh and
    /// asks for nothing more.
    @Test func aKeptSizeIsCheckedByOneMoreScanAndNoMore() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let aged = AgedRepos(fixture: fixture)
        let repo = try await aged.repo("india", days: 60, gitignore: ProjectFoldersDemo.gitignore, files: ["package-lock.json": "{}\n"])
        let sibling = fixture.scanRoot.appending(path: "india-done", directoryHint: .isDirectory)
        try await aged.git(["worktree", "add", "--quiet", "-b", "done", sibling.path], in: repo, days: 45)
        try await aged.commitAndPush(sibling, file: "notes/done.md", branch: "done", days: 45)
        try aged.blob(in: sibling, "node_modules/react/index.bin", megabytes: 4)

        // A du that, while `hold` exists, waits for `release` and only then measures (a scan that gets here late).
        let gate = fixture.url.appending(path: "gate", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: gate, withIntermediateDirectories: true)
        let script = fixture.url.appending(path: "late-du")
        try Data("""
        #!/bin/sh
        G='\(gate.path)'
        if [ -e "$G/hold" ]; then
          touch "$G/started.$$"
          while [ ! -e "$G/release" ]; do sleep 0.05; done
        fi
        exec /usr/bin/du "$@"
        """.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        var environment = fixture.environment(scanRoots: [fixture.scanRoot])
        environment.tools.du = script
        let app = AppModel(environment: environment, git: fixture.git)
        await app.refresh()
        let model = showingAll(WorktreesModel(app: app))
        let scans = app.scanCount

        FileManager.default.createFile(atPath: gate.appending(path: "hold").path, contents: nil)
        app.requestRefresh()
        func started() -> Int {
            ((try? FileManager.default.contentsOfDirectory(atPath: gate.path)) ?? []).filter { $0.hasPrefix("started.") }.count
        }
        #expect(await eventually { started() >= 2 }, "both of the scan's du calls started within \(TestWait.limit)")
        try FileManager.default.removeItem(at: gate.appending(path: "hold"))

        let report = await model.confirmLightClean(await model.prepareLightClean(model.ids([sibling])))
        #expect(report.deletedCount == 1)
        #expect((model.row(sibling)?.sizeBytes ?? .max) < 1024 * 1024)
        try aged.blob(in: sibling, "node_modules/react/index.bin", megabytes: 4)  // npm install again
        FileManager.default.createFile(atPath: gate.appending(path: "release").path, contents: nil)
        #expect(await eventually { !app.isScanning }, "the scans didn't end within \(TestWait.limit)")
        #expect((model.row(sibling)?.sizeBytes ?? 0) >= 4 * 1024 * 1024, "the folder holds 4 MB again")
        #expect(app.scanCount == scans + 2, "the running scan and one more")
        #expect(app.cleanupFacts.sizes.isEmpty)

        // No loop: nothing more is scanned afterwards.
        try await Task.sleep(for: .milliseconds(300))
        #expect(!app.isScanning && app.scanCount == scans + 2)
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
