@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// The P10 review's findings 1–5, from the reviewer's probes A, B, C, E and S, each with the safe expectation.
@Suite("Project folders review fixes")
@MainActor
struct ProjectsReviewTests {
    /// `india`, idle 60 days, whose node_modules a Cursor worktree and a sibling (also 60 days) use through a symlink.
    @MainActor private struct India {
        let fixture: GitFixture
        let models: ScreenModels
        let india: URL
        let cursor: URL
        let sibling: URL
        var projects: ProjectsModel { models.projects }
        var row: ProjectRow? { projects.allRows.first { CanonicalPath.same($0.url, india) } }
    }

    private func makeIndia() async throws -> India {
        let fixture = try GitFixture()
        let aged = AgedRepos(fixture: fixture)
        let india = try await aged.repo("india", days: 60, gitignore: ProjectFoldersDemo.gitignore, files: ["package-lock.json": "{}\n"])
        try aged.blob(in: india, "node_modules/react/blob.bin", megabytes: 1)
        let cursor = fixture.environment().cursorWorktreesDirectory.appending(path: "india/abc1", directoryHint: .isDirectory)
        let sibling = fixture.scanRoot.appending(path: "india-feature", directoryHint: .isDirectory)
        try await aged.git(["worktree", "add", "--quiet", "--detach", cursor.path], in: india, days: 60)
        try await aged.git(["worktree", "add", "--quiet", "-b", "feature", sibling.path], in: india, days: 60)
        for worktree in [cursor, sibling] {
            try FileManager.default.createSymbolicLink(at: worktree.appending(path: "node_modules"), withDestinationURL: india.appending(path: "node_modules"))
            try await aged.age(worktree, days: 60)
        }
        try await aged.age(india, days: 60)
        let app = AppModel(environment: fixture.environment(scanRoots: [fixture.scanRoot]).withFakeTools(), git: fixture.git)
        let models = ScreenModels(app: app, runner: FakeToolchain().runner)
        await app.refresh()
        await models.projects.refresh()
        return India(fixture: fixture, models: models, india: india, cursor: cursor, sibling: sibling)
    }

    // Finding 1 (probe A).
    @Test func aMainCheckoutUsedThroughASymlinkFromAnOutsideWorktreeIsInUse() async throws {
        let world = try await makeIndia()
        defer { world.fixture.remove() }
        let model = world.projects
        let quiet = try #require(world.row)
        #expect(quiet.isReady, "nothing runs anywhere yet: \(quiet.statusText)")

        // A process works in the Cursor worktree: in use at scan time, never picked, left alone by the sheet.
        let shell = SleepingProcess(seconds: 600)
        defer { shell.stop() }
        try shell.start(in: world.cursor)
        await model.refresh()
        let row = try #require(world.row)
        #expect(row.statusText.hasPrefix("In use (sleep"), "\(row.statusText)")
        #expect(!row.isReady)
        model.selectAllIdle()
        #expect(model.selection.isEmpty)
        let sheet = await model.prepareClean([row.id])
        #expect(sheet.cleanable.isEmpty)
        #expect(sheet.others.first?.lightClean.blocker?.contains("another worktree of this repo") == true,
                "\(sheet.others.first?.lightClean.blocker ?? "")")
        shell.stop()

        // Looked at while nothing ran, then a process starts in the sibling: refused right before its turn.
        let confirmation = await model.prepareClean([row.id])
        #expect(confirmation.cleanable.count == 1)
        let other = SleepingProcess(seconds: 600)
        defer { other.stop() }
        try other.start(in: world.sibling)
        let report = await model.cleanSelected(confirmation)
        #expect(report.deletedCount == 0)
        #expect(report.outcomes.first?.error?.contains("another worktree of this repo") == true, "\(report.outcomes.first?.error ?? "")")
        #expect(FileManager.default.fileExists(atPath: world.india.appending(path: "node_modules/react/blob.bin").path))
        #expect(FileManager.default.fileExists(atPath: world.cursor.appending(path: "node_modules/react/blob.bin").path), "the link still resolves")
        #expect(try RemovalLog(environment: world.models.app.environment).entries().isEmpty)
    }

    // Finding 1, idle side: work in an outside worktree makes the main checkout recent.
    @Test func workInAnOutsideWorktreeMakesTheMainCheckoutRecent() async throws {
        let world = try await makeIndia()
        defer { world.fixture.remove() }
        try world.fixture.write("today\n", to: "src/today.txt", in: world.sibling)
        await world.projects.refresh()
        let row = try #require(world.row)
        #expect(row.idleDays == 0)
        #expect(row.status == .recent(days: 0))
    }

    // Finding 2 (probe C): idle days are read now, not taken from an older worktree scan.
    @Test func idleDaysAreReadWhenTheProjectsAreScanned() async throws {
        let world = try await ProjectsWorld.make(scanProjects: false)
        defer { world.remove() }
        let aged = AgedRepos(fixture: world.fixture)
        let kilo = try await aged.repo("kilo", days: 60, gitignore: ProjectFoldersDemo.gitignore)
        let kiloWorktree = world.fixture.scanRoot.appending(path: "kilo-wt", directoryHint: .isDirectory)
        try await aged.git(["worktree", "add", "--quiet", "-b", "wt", kiloWorktree.path], in: kilo, days: 60)
        try aged.blob(in: kiloWorktree, "node_modules/x/blob.bin", megabytes: 1)
        try await aged.age(kiloWorktree, days: 60)
        try await aged.age(kilo, days: 60)
        await world.app.refresh()
        #expect(world.app.assessments.first { $0.worktree.url.lastPathComponent == "kilo-wt" }?.idle.idleDays == 60)

        // After the worktree scan: work in kilo-wt and in the Claude worktree inside delta.
        try world.fixture.write("today\n", to: "src/today.txt", in: kiloWorktree)
        try world.fixture.write("today\n", to: "notes/today.md", in: world.url("quiet-heron"))
        await world.projects.loadIfNeeded()

        let model = world.projects
        model.filter = .all
        #expect(world.row("kilo-wt")?.idleDays == 0)
        #expect(world.row("delta")?.idleDays == 0, "its Claude worktree was worked in")
        model.selectAllIdle()
        #expect(Set(model.selectedRows.map(\.name)) == ["echo", "foxtrot"])
    }

    // Finding 3 (probe B): what Select all idle picked is checked again; changed ones aren't deleted unless ticked.
    @Test func aPickedProjectThatChangedSinceIsNotDeletedUnlessTicked() async throws {
        let world = try await ProjectsWorld.make()
        defer { world.remove() }
        let model = world.projects
        model.selectAllIdle()
        #expect(Set(model.selectedRows.map(\.name)) == ["delta", "echo", "foxtrot"])
        #expect(model.autoPicked == model.selection)
        // golf added by hand: not auto-picked.
        model.filter = .all
        model.selection.insert(try #require(world.row("golf")).id)
        #expect(model.autoPicked.count == 3)

        // foxtrot is worked on, echo's idle clock becomes unknown (a transcript folder it can't read).
        try world.fixture.write("print('wip')\n", to: "wip.py", in: world.url("foxtrot"))
        let transcripts = world.environment.claudeConfigDirectory
            .appending(path: "projects/" + TranscriptFolderEncoding.encode(CanonicalPath.resolve(world.url("echo"))))
        try FileManager.default.createDirectory(at: transcripts, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: transcripts.path)

        await model.beginClean()
        let confirmation = try #require(model.confirmation)
        #expect(Set(confirmation.changed.map(\.name)) == ["echo", "foxtrot"])
        #expect(Set(confirmation.cleanable.map(\.name)) == ["delta", "golf"], "golf was picked by hand")
        #expect(confirmation.cleanable.first { $0.name == "golf" }?.idleNote == "You worked here 3 days ago; it will need a reinstall.")
        #expect(confirmation.title == "Clean 2 projects?")

        // foxtrot ticked by hand; echo left unticked.
        let foxtrot = try #require(confirmation.changed.first { $0.name == "foxtrot" })
        model.setIncluded(foxtrot.id, true)
        let ticked = try #require(model.confirmation)
        #expect(Set(ticked.cleanable.map(\.name)) == ["delta", "golf", "foxtrot"])
        let report = await model.cleanSelected(ticked)

        #expect(!world.exists("node_modules", in: "delta") && !world.exists("node_modules", in: "golf"))
        #expect(!world.exists(".venv", in: "foxtrot"), "ticked")
        #expect(world.exists("wip.py", in: "foxtrot"))
        #expect(world.exists(".dart_tool", in: "echo") && world.exists("ios/Pods", in: "echo"), "changed and not ticked")
        #expect(report.outcomes.count == 3)
    }

    // Finding 4 (probe E): growth below a first-level folder is seen on the next scan.
    @Test func aFolderThatGrewIsMeasuredAgain() async throws {
        let world = try await ProjectsWorld.make()
        defer { world.remove() }
        let before = try #require(world.row("delta")).sizeBytes
        try AgedRepos(fixture: world.fixture).blob(in: world.url("delta"), ".next/cache/big.bin", megabytes: 40)
        await world.projects.refresh()
        #expect(try #require(world.row("delta")).sizeBytes >= before + 40 * 1024 * 1024)
    }

    // Finding 5 (probe S): a light clean from the Worktrees screen, and one by the CLI, show up here.
    @Test func lightCleansDoneElsewhereUpdateTheListAndTheOverview() async throws {
        let world = try await ProjectsWorld.make()
        defer { world.remove() }
        let before = world.projects.idleTotal
        let worktrees = world.models.worktrees
        let confirmation = await worktrees.prepareLightClean(worktrees.ids([world.url("delta")]))
        _ = await worktrees.confirmLightClean(confirmation)
        #expect(!world.exists("node_modules", in: "delta"))

        #expect(await eventually { world.row("delta") == nil }, "delta has nothing left to clean")
        #expect(world.projects.idleTotal.count == before.count - 1)
        #expect(world.models.overview.summary.bytes(.projectFolders) == world.projects.idleTotal.bytes)

        // The CLI cleans foxtrot (in this fixture); the app sees it on its next scan.
        let environment = world.environment
        let result = try await ProcessRunner.run(
            executable: try CLIBinary.url(),
            arguments: ["light-clean", world.url("foxtrot").path, "--root", world.fixture.scanRoot.path, "--yes"],
            environmentAdditions: [
                "BONSAI_SETTINGS_DIR": environment.settingsDirectory.path,
                "CLAUDE_CONFIG_DIR": environment.claudeConfigDirectory.path,
            ],
            timeout: .seconds(120)
        )
        #expect(result.succeeded, "\(result.stderr)")
        #expect(!world.exists(".venv", in: "foxtrot"))
        #expect(world.row("foxtrot") != nil, "not seen before the next scan")
        await world.app.refresh()
        #expect(await eventually { world.row("foxtrot") == nil })
        #expect(world.projects.idleTotal.count == before.count - 2)
    }
}
