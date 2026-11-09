@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Project folders model")
@MainActor
struct ProjectsModelTests {
    private func names(_ rows: [ProjectRow]) -> Set<String> {
        Set(rows.map(\.name))
    }

    @Test func theIdleFilterShowsIdleProjectsAndSelectAllIdlePicksOnlyReadyOnes() async throws {
        let world = try await ProjectsWorld.make(unknownIdle: true)
        defer { world.remove() }
        let model = world.projects
        #expect(model.threshold == 30)
        #expect(model.filter == .idle)
        #expect(model.filterTitle(.idle) == "Idle 30+ days")

        #expect(names(model.rows) == ["delta", "echo", "foxtrot"])
        model.filter = .all
        #expect(names(model.rows) == ["delta", "echo", "foxtrot", "golf", "hotel"])

        let golf = try #require(world.row("golf"))
        #expect(golf.idleDays == 3)
        #expect(golf.status == .recent(days: 3))
        #expect(golf.statusText == "Recent")
        #expect(golf.recentNote == "You worked here 3 days ago; it will need a reinstall.")
        let hotel = try #require(world.row("hotel"))
        #expect(hotel.idleDays == nil, "the transcript folder can't be read")
        #expect(hotel.status == .idleUnknown)
        #expect(hotel.idleText == "unknown")

        model.selectAllIdle()
        #expect(Set(model.selectedRows.map(\.name)) == ["delta", "echo", "foxtrot"], "not the recent one, not the unknown one")
        #expect(model.idleTotal.count == 3)
        #expect(model.idleTotal.bytes == model.selectedRows.reduce(0) { $0 + $1.sizeBytes })
        #expect(model.allTotal.count == 5)

        let delta = try #require(world.row("delta"))
        #expect(delta.foldersText == ".next, node_modules")
        #expect(delta.sizeBytes >= 5 * 1024 * 1024)
        #expect(delta.project.rebuildLines == ["npm install", ".next comes back with next build or next dev"])
        let echo = try #require(world.row("echo"))
        #expect(echo.foldersText == ".dart_tool, build, Pods")
        #expect(echo.project.rebuildLines == ["flutter pub get", "pod install (in ios)"])
        #expect(world.row("foxtrot")?.project.rebuildLines == ["recreate the virtualenv"])

        // Grouped by repo, biggest first; each main checkout is its own group here.
        #expect(model.groups.first?.name == "delta")
        #expect(model.tableItems.count == model.groups.count * 2)
        model.toggleExpanded(delta.worktree.repoPath)
        #expect(!model.selection.contains(delta.id), "closing a group deselects its rows")
        #expect(model.tableItems.count == model.groups.count * 2 - 1)
    }

    @Test func claudeAndCursorWorktreesAreCountedInTheFooterNotListed() async throws {
        let world = try await ProjectsWorld.make()
        defer { world.remove() }
        let model = world.projects
        model.filter = .all
        #expect(world.app.assessments.contains { $0.worktree.kind == .claude })
        #expect(!model.allRows.contains { $0.kind == .claude || $0.kind == .cursor })
        #expect(model.leftOut?.count == 1)
        #expect(model.leftOutText == "1 Claude/Cursor worktree holds 1.0 MB more; see Worktrees")
    }

    @Test func cleaningTwoIdleProjectsDeletesTheirFoldersOnlyAndLogsEach() async throws {
        let world = try await ProjectsWorld.make()
        defer { world.remove() }
        let model = world.projects
        let scans = world.app.scanCount
        model.selection = world.ids(["delta", "echo"])

        await model.beginClean()
        #expect(model.isShowingCleanSheet && !model.isPreparingClean)
        let confirmation = try #require(model.confirmation)
        #expect(confirmation.cleanable.count == 2)
        #expect(confirmation.folderCount == 5)
        #expect(confirmation.title == "Clean 2 projects?")
        #expect(confirmation.deleteButtonTitle == "Delete 5 folders")
        #expect(confirmation.estimatedTotalBytes >= 9 * 1024 * 1024)
        #expect(confirmation.summary.hasPrefix("2 projects, 5 folders, about "))
        let delta = try #require(confirmation.cleanable.first { $0.name == "delta" })
        #expect(delta.rebuildLines == ["npm install", ".next comes back with next build or next dev"])
        #expect(delta.idleNote == nil, "idle 60 days")
        #expect(delta.candidates.allSatisfy { $0.estimatedBytes != nil }, "measured afresh for the log")

        let report = await model.cleanSelected(confirmation)

        #expect(report.deletedCount == 5)
        #expect(report.notDeletedCount == 0)
        #expect(report.outcomes.count == 2)
        #expect(report.outcomes.allSatisfy { $0.error == nil && $0.freedBytes != nil })
        for folder in ["node_modules", ".next"] { #expect(!world.exists(folder, in: "delta")) }
        for folder in [".dart_tool", "build", "ios/Pods"] { #expect(!world.exists(folder, in: "echo")) }
        for file in ["package-lock.json", "next.config.mjs", "package.json", ".gitignore"] { #expect(world.exists(file, in: "delta")) }
        for file in ["pubspec.yaml", "ios/Podfile"] { #expect(world.exists(file, in: "echo")) }
        #expect(world.exists("node_modules/react/blob.bin", in: "quiet-heron"), "the Claude worktree inside delta is untouched")
        #expect(world.exists(".venv/lib/blob.bin", in: "foxtrot"), "not selected, not touched")

        let entries = try world.logEntries()
        #expect(entries.count == 5)
        #expect(entries.allSatisfy { $0.action == .lightClean && $0.mode == .manual })
        #expect(Set(entries.map { URL(fileURLWithPath: $0.path).lastPathComponent }) == ["node_modules", ".next", ".dart_tool", "build", "Pods"])
        #expect(world.app.logEntries.count == 5, "the app re-read the log")
        #expect(world.app.scanCount == scans, "the cleaned checkouts were measured again, not every worktree")
        // The cleaned projects were looked at again: nothing left, so they are gone from the list.
        #expect(world.row("delta") == nil && world.row("echo") == nil)
        #expect(world.row("foxtrot") != nil)
        #expect(model.cleanReport?.deletedCount == 5)
        #expect(!model.isCleaning)

        model.dismissClean()
        #expect(!model.isShowingCleanSheet && model.confirmation == nil && model.cleanReport == nil)
    }

    @Test func aFolderThatChangedAfterTheLookIsRefusedAndTheRunGoesOn() async throws {
        let world = try await ProjectsWorld.make()
        defer { world.remove() }
        let model = world.projects
        let confirmation = await model.prepareClean(world.ids(["delta", "echo"]))
        #expect(confirmation.folderCount == 5)

        // After the user looked, a new file shows up in delta's node_modules and git now lists it.
        try world.fixture.write("mine\n", to: "node_modules/patch.js", in: world.url("delta"))
        try await world.fixture.run(["add", "-f", "node_modules/patch.js"], in: world.url("delta"))

        let report = await model.cleanSelected(confirmation)

        let delta = try #require(report.outcomes.first { $0.item.worktree.url.lastPathComponent == "delta" })
        let modules = try #require(delta.folders.first { $0.relativePath == "node_modules" })
        guard case .refused(let why) = modules.status else {
            Issue.record("expected a refusal, got \(modules.status)")
            return
        }
        #expect(why.contains("git"), "\(why)")
        #expect(world.exists("node_modules/patch.js", in: "delta"), "the new file and its folder stay")
        #expect(world.exists("node_modules/next/dist/blob.bin", in: "delta"))
        #expect(!world.exists(".next", in: "delta"), "the folder that didn't change went")
        for folder in [".dart_tool", "build", "ios/Pods"] { #expect(!world.exists(folder, in: "echo"), "the next project ran") }
        #expect(report.deletedCount == 4)
        #expect(try world.logEntries().count == 4, "refused folders aren't logged")
        // Looked at again: node_modules now holds a file git tracks, so delta has nothing left to clean.
        #expect(world.row("delta") == nil)
    }

    @Test func aProjectWhoseHeadMovedSinceTheLookIsRefusedWhole() async throws {
        let world = try await ProjectsWorld.make()
        defer { world.remove() }
        let model = world.projects
        let confirmation = await model.prepareClean(world.ids(["delta", "foxtrot"]))
        #expect(confirmation.cleanable.count == 2)

        // A commit in delta after the user looked: the record the sheet showed (its expectation) no longer holds.
        try world.fixture.write("v2\n", to: "CHANGELOG.md", in: world.url("delta"))
        try await world.fixture.commitAll(in: world.url("delta"), message: "Release")

        let report = await model.cleanSelected(confirmation)

        let delta = try #require(report.outcomes.first { $0.item.worktree.url.lastPathComponent == "delta" })
        #expect(delta.error?.contains("changed since it was listed") == true, "\(delta.error ?? "")")
        #expect(delta.deletedCount == 0)
        #expect(world.exists("node_modules", in: "delta") && world.exists(".next", in: "delta"))
        #expect(!world.exists(".venv", in: "foxtrot"), "the next project was still cleaned")
        #expect(try world.logEntries().count == 1)
    }

    @Test func aProcessInsideIsInUseAtScanAndAtCleanTime() async throws {
        let world = try await ProjectsWorld.make()
        defer { world.remove() }
        let model = world.projects

        // Looked at, then a process starts inside: the cleaner's own check refuses it.
        let confirmation = await model.prepareClean(world.ids(["foxtrot"]))
        #expect(confirmation.cleanable.count == 1)
        let shell = SleepingProcess(seconds: 600)
        defer { shell.stop() }
        try shell.start(in: world.url("foxtrot"))
        let report = await model.cleanSelected(confirmation)
        #expect(report.deletedCount == 0)
        #expect(report.outcomes.first?.error?.contains("working folder inside") == true, "\(report.outcomes.first?.error ?? "")")
        #expect(world.exists(".venv/lib/blob.bin", in: "foxtrot"))
        #expect(try world.logEntries().isEmpty)

        // A fresh scan shows it in use, and Select all idle leaves it out.
        await model.refresh()
        let row = try #require(world.row("foxtrot"))
        #expect(row.statusText.hasPrefix("In use (sleep"), "\(row.statusText)")
        #expect(!row.isReady)
        model.selectAllIdle()
        #expect(Set(model.selectedRows.map(\.name)) == ["delta", "echo"])
        // Picked by hand, the sheet lists nothing to delete there, with the process.
        let again = await model.prepareClean([row.id])
        #expect(again.cleanable.isEmpty)
        #expect(again.others.first?.lightClean.blocker?.contains("sleep") == true)
    }

    @Test func aProjectBelowTheThresholdCanBeCleanedByHandWithANote() async throws {
        let world = try await ProjectsWorld.make()
        defer { world.remove() }
        #expect(await world.projects.prepareClean(world.ids(["golf"])).items.isEmpty, "hidden by the idle filter")
        world.projects.filter = .all
        let confirmation = await world.projects.prepareClean(world.ids(["golf"]))
        let item = try #require(confirmation.cleanable.first)
        #expect(item.idleNote == "You worked here 3 days ago; it will need a reinstall.")
        #expect(item.rebuildLines == ["yarn"])
        let report = await world.projects.cleanSelected(confirmation)
        #expect(report.deletedCount == 1)
        #expect(!world.exists("node_modules", in: "golf"))
        #expect(world.exists("yarn.lock", in: "golf"))
    }

    @Test func oneCleanupAtATime() async throws {
        let gate = ProcessGate(stage: "lsof")
        let world = try await ProjectsWorld.make(gate: gate)
        defer { world.remove() }
        let model = world.projects
        let confirmation = await model.prepareClean(world.ids(["delta", "echo"]))

        // Another cleanup of this app holds the guard: refused, nothing deleted.
        let inside = await world.app.cleaningUp { await model.cleanSelected(confirmation) }
        let refused = try #require(inside)
        #expect(refused.deletedCount == 0)
        #expect(refused.outcomes.allSatisfy { $0.error == "another cleanup is still running; nothing was deleted" })

        // Another Bonsai holds cleanup.lock.
        let lock = try #require(try CleanupLock.tryAcquire(environment: world.environment))
        let locked = await model.cleanSelected(confirmation)
        lock.release()
        #expect(locked.outcomes.first?.error == "\(CleanupLock.busyMessage); nothing was deleted")
        #expect(world.exists("node_modules", in: "delta"))

        // While the clean runs (stopped at its first process check), a manual removal is refused.
        let removal = await world.models.worktrees.prepareRemoval(
            world.models.worktrees.ids([world.url("quiet-heron")])
        )
        #expect(removal.allowed.count == 1)
        gate.arm()
        let running = Task { await model.cleanSelected(confirmation) }
        #expect(await eventually { gate.isWaiting })
        #expect(model.isCleaning && world.app.isCleaningUp)
        let outcomes = await world.models.worktrees.confirmRemoval(removal)
        gate.open()
        let report = await running.value
        #expect(outcomes.first?.error == "another cleanup is still running")
        #expect(FileManager.default.fileExists(atPath: world.url("quiet-heron").path), "not removed")
        #expect(report.deletedCount == 5)
        #expect(try world.logEntries().count == 5)
    }

    @Test func aCleanThatEndsDuringAFullScanIsLookedAtAgainWhenTheScanEnds() async throws {
        let gate = ProcessGate(stage: "lsof")
        let world = try await ProjectsWorld.make(gate: gate)
        defer { world.remove() }
        let model = world.projects
        let confirmation = await model.prepareClean(world.ids(["delta"]))

        // A full scan has started and stops at its process listing.
        gate.arm()
        let scan = Task { await model.refresh() }
        #expect(await eventually { gate.isWaiting })
        #expect(model.isScanning)
        let report = await model.cleanSelected(confirmation)
        #expect(report.deletedCount == 2)
        #expect(world.row("delta") != nil, "left for the running scan to finish first")

        gate.open()
        await scan.value
        #expect(!model.isScanning)
        #expect(world.row("delta") == nil, "looked at again once the scan ended")
        #expect(world.row("echo") != nil)
    }

    @Test func theOverviewCardSumsIdleProjectsAndOpensTheScreenOnThem() async throws {
        let world = try await ProjectsWorld.make(scanProjects: false)
        defer { world.remove() }
        let overview = world.models.overview
        #expect(overview.summary.state(.projectFolders) == .notMeasured)
        #expect(overview.card(.projectFolders) == nil)
        #expect(overview.measuringText?.contains("Project folders") == true)

        await world.projects.loadIfNeeded()
        let card = try #require(overview.card(.projectFolders))
        #expect(card.bytes == world.projects.idleTotal.bytes, "the footer's Ready to clean is the card's number")
        #expect(card.bytes >= 10 * 1024 * 1024)
        #expect(card.detail == "Dependency and build folders of 3 projects idle 30+ days")
        overview.open(.projectFolders)
        #expect(world.models.navigation.section == .projects)
        #expect(world.projects.filter == .canFree)
        #expect(Set(world.projects.rows.map(\.id)) == Set(world.projects.reclaimableRows.map(\.id)))
    }
}
