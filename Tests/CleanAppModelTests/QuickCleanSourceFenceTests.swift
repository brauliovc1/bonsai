@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Quick clean protected source scopes", .serialized)
@MainActor
struct QuickCleanSourceFenceTests {
    @Test func aScannedMainCheckoutInsideACacheTargetKeepsItsSource() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let cache = fixture.home.appending(path: ".npm/_cacache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let aged = AgedRepos(fixture: fixture)
        let repo = try await aged.repo("protected-source", days: 8, gitignore: "", files: ["source.swift": "let personalWork = 42\n"], in: cache)
        try fixture.write("private committed work\n", to: "private.swift", in: repo)
        try await aged.git(["add", "private.swift"], in: repo, days: 8)
        try await aged.git(["commit", "--quiet", "-m", "Unpublished main work"], in: repo, days: 8)
        #expect(try await fixture.run(["rev-list", "--count", "HEAD", "--not", "--remotes"], in: repo) == "1")
        try fixture.write("unpublished personal work\n", to: "draft.txt", in: repo)
        try await aged.age(repo, days: 8)
        let environment = fixture.environment(scanRoots: [repo]).withFakeTools(docker: false, xcrun: false, developerTools: false)
        try SettingsStore(environment: environment).save(Settings(scanRoots: [repo.path], idleThresholdDays: 30))
        let app = AppModel(environment: environment, git: fixture.git)
        let tools = FakeToolchain()
        let models = ScreenModels(app: app, runner: tools.runner, processes: ProcessSource { ProcessList(processes: []) })
        await models.quickClean.begin()
        try #require(app.scan?.worktrees.contains { $0.isMain && CanonicalPath.same($0.url, repo) } == true)
        let cacheItems = models.quickClean.preview?.groups.first { $0.id == .toolCaches }?.items ?? []
        #expect(!cacheItems.contains { $0.id == "cache:npm" }, "A cache cleanup must not bypass the protected scanned repo because it has no deletion operation of its own.")

        if models.quickClean.confirm() != nil { await app.cleanupQueue.waitUntilEmpty() }

        #expect(FileManager.default.fileExists(atPath: repo.appending(path: "source.swift").path))
        #expect(FileManager.default.fileExists(atPath: repo.appending(path: ".git").path))
        #expect(FileManager.default.fileExists(atPath: repo.appending(path: "draft.txt").path))
    }

    @Test(arguments: [false, true])
    func discoveredRootsAreProtectedEvenWithoutWorktreeRecords(_ targetInsideRepo: Bool) async throws {
        let world = try await QuickCleanTestWorld.make()
        defer { world.remove() }
        let fence = QuickCleanSourceFence(environment: world.app.environment, git: world.fixture.git,
            roots: [], repositories: [world.main.path], worktrees: [])
        let scope = targetInsideRepo ? world.main.appending(path: "node_modules") : world.main.deletingLastPathComponent()
        #expect(fence.reason(paths: [scope.path], broad: true) != nil)
    }

    @Test func configuredSourceDomainProtectsCheckoutsThatHaveNotAppearedYet() async throws {
        let world = try await QuickCleanTestWorld.make()
        defer { world.remove() }
        let cache = world.app.environment.homeDirectory.appending(path: ".npm/_cacache")
        let futureSource = cache.appending(path: "future-projects")
        let fence = QuickCleanSourceFence(environment: world.app.environment, git: world.fixture.git,
            roots: [futureSource], repositories: [], worktrees: [])
        #expect(fence.reason(paths: [cache.path], broad: true) != nil)
    }

    @Test func freshSourceListingFailureRefusesBroadCleanup() async throws {
        let world = try await QuickCleanTestWorld.make()
        defer { world.remove() }
        var unavailable = world.fixture.git
        unavailable.executable = world.fixture.url.appending(path: "missing-git-tool")
        let fence = QuickCleanSourceFence(environment: world.app.environment, git: unavailable,
            roots: [], repositories: [world.main.path], worktrees: [])
        let scope = world.app.environment.homeDirectory.appending(path: ".npm/_cacache")
        #expect(await fence.freshReason(paths: [scope.path])?.contains("could not be listed") == true)
    }

    @Test func aNewlyFilledCacheTargetCannotConsumeAWorktreeMovedThereWhileQueued() async throws {
        let world = try await QuickCleanTestWorld.make()
        defer { world.remove() }
        let home = world.app.environment.homeDirectory
        let cache = home.appending(path: ".npm/_cacache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("cache".utf8).write(to: cache.appending(path: "blob"))
        let gate = QueueGate()
        defer { gate.open() }
        _ = try #require(world.app.cleanupQueue.enqueue(title: "Review gate", unit: "steps", work: [queueWork("test:source-fence") {
            await gate.wait(); return CleanupItemResult(.refused, detail: "Read-only gate")
        }]))
        try #require(await eventually { gate.entered })
        await world.quick.begin()
        #expect(world.group(.toolCaches).contains { $0.id == "cache:npm" })
        let task = try #require(world.quick.confirm())
        let freshTarget = home.appending(path: ".npm/_npx")
        try FileManager.default.createDirectory(at: freshTarget, withIntermediateDirectories: true)
        let moved = freshTarget.appending(path: "protected-worktree")
        try await world.fixture.run(["worktree", "move", world.old.path, moved.path], in: world.main)
        try world.fixture.write("unpublished draft\n", to: "draft.txt", in: moved)
        gate.open()
        await world.app.cleanupQueue.waitUntilEmpty()
        #expect(world.exists(moved.appending(path: "draft.txt")) && world.exists(moved.appending(path: ".git")))
        #expect(world.exists(cache.appending(path: "blob")))
        #expect(task.items.first { $0.resources.contains("cache:npm") }?.state == .refused)
    }

    @Test func simulatorSourceFenceRunsAfterItsLastDeviceListing() async throws {
        let world = try await QuickCleanTestWorld.make(commands: true)
        defer { world.remove() }
        await world.quick.begin()
        #expect(world.group(.simulators).count == 2)
        try world.fixture.write("unpublished draft\n", to: "draft.txt", in: world.old)
        let gate = CallGate()
        defer { gate.release() }
        world.tools.hold = gate.hold { $0.arguments == ["simctl", "list", "devices", "-j"] }
        let task = try #require(world.quick.confirm())
        try #require(await eventually { gate.isReached })
        let device = world.app.environment.homeDirectory.appending(path: "Library/Developer/CoreSimulator/Devices/BBBB")
        try FileManager.default.createDirectory(at: device, withIntermediateDirectories: true)
        let moved = device.appending(path: "protected-source")
        try await world.fixture.run(["worktree", "move", world.old.path, moved.path], in: world.main)
        gate.release()
        await world.app.cleanupQueue.waitUntilEmpty()
        #expect(world.tools.deleteCalls.isEmpty && world.exists(moved.appending(path: "draft.txt")))
        #expect(task.items.first { $0.resources.contains(DockerSimulatorsModel.simulatorsResource) }?.state == .refused)
    }

}
