@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// The P10 reviewer's probes that found nothing wrong (I, L, U, V), kept so it stays that way.
@Suite("Project folders edges")
@MainActor
struct ProjectsEdgeTests {
    // Probe V: untracked work (not ignored, through a .gitignore negation) appears in node_modules after the look.
    @Test func untrackedWorkInAFolderAfterTheLookIsRefusedAndTheRunGoesOn() async throws {
        let world = try await ProjectsWorld.make()
        defer { world.remove() }
        let model = world.projects
        let confirmation = await model.prepareClean(world.ids(["delta", "foxtrot"]))
        let delta = world.url("delta")
        try world.fixture.write(ProjectFoldersDemo.gitignore + "!node_modules/\nnode_modules/*\n!node_modules/mine/\n", to: ".gitignore", in: delta)
        try world.fixture.write("my work\n", to: "node_modules/mine/work.txt", in: delta)
        #expect(try await world.fixture.run(["status", "--porcelain", "--untracked-files=all"], in: delta).contains("node_modules/mine/work.txt"))

        let report = await model.cleanSelected(confirmation)

        let modules = try #require(report.outcomes.first { $0.item.worktree.url.lastPathComponent == "delta" }?
            .folders.first { $0.relativePath == "node_modules" })
        guard case .refused = modules.status else {
            Issue.record("expected a refusal, got \(modules.status)")
            return
        }
        #expect(world.exists("node_modules/mine/work.txt", in: "delta"))
        #expect(!world.exists(".next", in: "delta"))
        #expect(!world.exists(".venv", in: "foxtrot"), "the next project ran")
    }

    // Probe I: node_modules swapped for a symlink to another project's folder after the look.
    @Test func aFolderSwappedForASymlinkAfterTheLookIsRefused() async throws {
        let world = try await ProjectsWorld.make()
        defer { world.remove() }
        let confirmation = await world.projects.prepareClean(world.ids(["delta"]))
        let modules = world.url("delta").appending(path: "node_modules")
        try FileManager.default.moveItem(at: modules, to: world.url("delta").appending(path: "nm_real"))
        try FileManager.default.createSymbolicLink(at: modules, withDestinationURL: world.url("foxtrot").appending(path: ".venv"))

        let report = await world.projects.cleanSelected(confirmation)

        #expect(report.deletedCount == 1, ".next only")
        #expect(world.exists(".venv/lib/blob.bin", in: "foxtrot"), "the link's target is untouched")
        #expect(world.exists("nm_real/next/dist/blob.bin", in: "delta"))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: modules.path)) != nil)
    }

    // Probe U: a process in the Claude worktree inside delta stops delta's clean.
    @Test func aProcessInTheClaudeWorktreeInsideStopsTheMainCheckout() async throws {
        let world = try await ProjectsWorld.make(scanProjects: false)
        defer { world.remove() }
        let shell = SleepingProcess()
        defer { shell.stop() }
        try shell.start(in: world.url("quiet-heron"))
        await world.projects.refresh()
        let delta = try #require(world.row("delta"))
        #expect(!delta.isReady)
        #expect(delta.statusText.hasPrefix("In use (\(SleepingProcess.command)"), "\(delta.statusText)")
        let confirmation = await world.projects.prepareClean([delta.id])
        #expect(confirmation.cleanable.isEmpty)
        // Even handed every item, nothing goes while the process is there.
        let forced = ProjectsConfirmation(items: confirmation.items.map {
            ProjectsConfirmation.Item(lightClean: LightCleanConfirmation.Item(
                worktree: $0.worktree, findings: $0.lightClean.findings, blocker: nil
            ), idle: $0.idle, threshold: $0.threshold, rebuildLines: [])
        })
        let report = await world.projects.cleanSelected(forced)
        #expect(report.deletedCount == 0)
        #expect(world.exists("node_modules", in: "delta"))
    }

    // Probe L: a Claude worktree can't get into the sheet.
    @Test func aClaudeWorktreeCannotBeSelectedOrCleanedHere() async throws {
        let world = try await ProjectsWorld.make()
        defer { world.remove() }
        let model = world.projects
        model.filter = .all
        let heron = try #require(world.app.assessments.first { $0.worktree.kind == .claude }).worktree
        model.selection = [heron.path]
        #expect(model.selectedRows.isEmpty)
        #expect(!model.canClean)
        #expect(await model.prepareClean([heron.path]).items.isEmpty)
    }
}
