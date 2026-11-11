@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@MainActor
private struct QuickCleanProcessWorld {
    let fixture: GitFixture
    let models: ScreenModels
    let tools: FakeToolchain
    let repo: URL
    let extra: URL?
    var quick: QuickCleanModel { models.quickClean }
    var queue: CleanupQueue { models.app.cleanupQueue }

    static func make(days: Int = 8, extra: Bool = true, gate: ProcessGate? = nil, sizes: Bool = true) async throws -> Self {
        let f = try GitFixture()
        let aged = AgedRepos(fixture: f)
        let repo = try await aged.repo("review-quick", days: days, gitignore: "node_modules/\n", files: ["README.md": "keep\n"])
        try aged.blob(in: repo, "node_modules/package/data", kibibytes: 8)
        var additional: URL?
        if extra {
            let path = f.scanRoot.appending(path: "review-quick-extra")
            try await aged.git(["worktree", "add", "--quiet", "-b", "review-extra", path.path], in: repo, days: days)
            try await aged.age(path, days: days)
            additional = path
        }
        try await aged.age(repo, days: days)
        var environment = f.environment(scanRoots: [f.scanRoot]).withFakeTools(docker: false, xcrun: false, developerTools: false)
        if !sizes { environment.tools.du = nil }
        if let gate {
            try gate.install(in: f.url, realGit: f.git.executable)
            environment.tools.lsof = gate.lsof
        }
        try SettingsStore(environment: environment).save(Settings())
        let app = AppModel(environment: environment, git: f.git)
        let tools = FakeToolchain()
        let models = ScreenModels(app: app, runner: tools.runner, processes: ProcessSource { ProcessList(processes: []) })
        return Self(fixture: f, models: models, tools: tools, repo: repo, extra: additional)
    }

    func has(_ kind: QuickCleanGroup.Kind, path: URL) -> Bool {
        quick.preview?.groups.first(where: { $0.id == kind })?.items.contains { item in
            item.paths.contains { CanonicalPath.same(URL(fileURLWithPath: $0), path) }
        } == true
    }
}

@Suite("Quick clean fresh linked processes", .serialized)
@MainActor
struct QuickCleanProcessRegressionTests {
    @Test func movingALinkedWorktreeDoesNotHideItsRunningProcess() async throws {
        let world = try await QuickCleanProcessWorld.make()
        defer { world.fixture.remove() }
        await world.quick.begin()
        let extra = try #require(world.extra)
        let folder = world.repo.appending(path: "node_modules")
        #expect(world.has(.projects, path: folder))
        let relocated = world.fixture.scanRoot.appending(path: "renamed-while-preview-open")
        try await world.fixture.run(["worktree", "move", extra.path, relocated.path], in: world.repo)
        let process = SleepingProcess()
        defer { process.stop() }
        try process.start(in: relocated)
        let records = try await WorktreeScanner(git: world.fixture.git,
            cursorWorktreesDirectory: world.models.app.environment.cursorWorktreesDirectory).worktrees(in: world.repo)
        let freshMain = try #require(records.first { $0.isMain })
        let activity = await ProjectFoldersScanner(git: world.fixture.git, environment: world.models.app.environment)
            .idleReport(for: freshMain, known: records)
        try #require(activity.idleDays.map { $0 >= 7 } == true, "Moving a quiet worktree preserves its source/HEAD/index dates; no artificial post-preview aging.")

        let task = try #require(world.quick.confirm())
        await world.queue.waitUntilEmpty()

        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "package/data").path))
        #expect(task.items.first { $0.resources.contains(CanonicalPath.resolve(folder)) }?.state == .refused)
        #expect(process.stop())
    }

    @Test func quittingDuringPostCleanupDoesNotStartAdditionalCategoryRefreshes() async throws {
        let world = try await QuickCleanProcessWorld.make()
        defer { world.fixture.remove() }
        let postItem = QueueGate()
        let lateRefresh = CallGate()
        defer { postItem.open(); lateRefresh.release() }
        world.models.app.whenCheckoutsChange { _ in await postItem.wait() }
        await world.quick.begin()
        // There are no DerivedData cleanup items. This command can only be a later category refresh.
        world.tools.hold = lateRefresh.hold { $0.executable == FakeToolchain.defaults }
        let task = try #require(world.quick.confirm())
        try #require(await eventually { postItem.entered })
        #expect(task.completedCount == task.items.count)
        var quitReturned = false
        let quitting = Task { await world.models.app.prepareToQuit(); quitReturned = true }
        try #require(await eventually { world.models.app.isQuitting })
        postItem.open()
        try #require(await eventually { quitReturned || lateRefresh.isReached })

        #expect(!lateRefresh.isReached, "Quit after the current item must not start a new defaults/category refresh that can wait for a tool timeout.")
        lateRefresh.release()
        await quitting.value
        await world.queue.waitUntilEmpty()
    }

}
