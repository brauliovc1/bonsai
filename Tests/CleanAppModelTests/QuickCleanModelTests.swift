@testable import CleanAppModel
@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Quick clean policy", .serialized)
@MainActor
struct QuickCleanModelTests {
    @Test func previewUsesSevenDaysWithoutSavingSettingsAndNeverStartsCleanup() async throws {
        let world = try await QuickCleanTestWorld.make()
        defer { world.remove() }
        let before = try Data(contentsOf: SettingsStore(environment: world.app.environment).fileURL)
        await world.quick.begin()
        #expect(world.quick.canConfirm)
        #expect(world.group(.worktrees).contains { world.matches($0.path, world.old) })
        #expect(world.group(.worktrees).allSatisfy { !world.matches($0.path, world.main) })
        #expect(world.group(.projects).contains { world.matches($0.path, world.main.appending(path: "node_modules")) })
        #expect(world.group(.projects).allSatisfy { !$0.paths.contains { CanonicalPath.resolve($0).hasPrefix(CanonicalPath.resolve(world.old) + "/") || CanonicalPath.resolve($0).hasPrefix(CanonicalPath.resolve(world.recent) + "/") } })
        #expect(world.app.settings.idleThresholdDays == 30)
        #expect(try Data(contentsOf: SettingsStore(environment: world.app.environment).fileURL) == before)
        #expect(world.app.cleanupQueue.tasks.isEmpty && world.tools.changingCalls.isEmpty)
        #expect(try RemovalLog(environment: world.app.environment).entries().isEmpty)
        #expect(world.exists(world.old) && world.exists(world.main.appending(path: "node_modules")))
    }

    @Test func localWorkAndUnknownActivityAreLeftAlone() async throws {
        let world = try await QuickCleanTestWorld.make(unknown: true)
        defer { world.remove() }
        try world.fixture.write("not committed\n", to: "work.txt", in: world.old)
        try await AgedRepos(fixture: world.fixture, now: world.now).age(world.old, days: 8)
        await world.quick.begin()
        #expect(world.group(.worktrees).isEmpty)
        #expect(world.group(.projects).allSatisfy { !world.matches($0.path, world.main.appending(path: "node_modules")) })
        #expect(world.exists(world.old.appending(path: "work.txt")))
    }

    @Test func oneConfirmationIsOneAtomicTaskAndCannotReplay() async throws {
        let world = try await QuickCleanTestWorld.make()
        defer { world.remove() }
        await world.quick.begin()
        let task = try #require(world.quick.confirm())
        #expect(world.quick.confirm() == nil && !world.quick.isPresented)
        #expect(world.app.cleanupQueue.tasks.count == 1 && task.unit == "steps")
        await world.app.cleanupQueue.waitUntilEmpty()
        #expect(!world.exists(world.old))
        #expect(world.quick.confirm() == nil && world.app.cleanupQueue.tasks.count == 1)
        #expect(world.exists(world.main) && world.exists(world.main.appending(path: "source.txt")))
        #expect(!world.exists(world.main.appending(path: "node_modules")))
        #expect(world.exists(world.recent.appending(path: "node_modules")))
        #expect(try await world.fixture.run(["rev-parse", "refs/heads/old-branch"], in: world.main).isEmpty == false)
    }

    @Test func activityAfterPreviewRefusesWorktreeEvenWithUnchangedContents() async throws {
        let world = try await QuickCleanTestWorld.make()
        defer { world.remove() }
        await world.quick.begin()
        try FileManager.default.setAttributes([.modificationDate: world.now], ofItemAtPath: world.old.appending(path: "source.txt").path)
        let task = try #require(world.quick.confirm())
        await world.app.cleanupQueue.waitUntilEmpty()
        #expect(world.exists(world.old))
        #expect(task.items.first { $0.resources.contains(CanonicalPath.resolve(world.old)) }?.result?.state == .refused)
    }

    @Test func finalWorktreeAdmissionCatchesActivityAfterSlowInspection() async throws {
        let world = try await QuickCleanTestWorld.make()
        defer { world.remove() }
        let source = world.old.appending(path: "source.txt"), now = world.now.addingTimeInterval(-7 * 86400 - 3600)
        world.quick.configureRemover = { remover in
            remover.afterInspection = { try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: source.path) }
        }
        await world.quick.begin()
        let task = try #require(world.quick.confirm())
        await world.app.cleanupQueue.waitUntilEmpty()
        #expect(world.exists(world.old))
        #expect(task.items.first { $0.resources.contains(CanonicalPath.resolve(world.old)) }?.result?.state == .refused)
    }

    @Test func finalProjectAdmissionCatchesActivityAfterCandidateRecheck() async throws {
        let world = try await QuickCleanTestWorld.make()
        defer { world.remove() }
        let source = world.main.appending(path: "source.txt"), now = world.now.addingTimeInterval(-7 * 86400 - 3600)
        world.quick.configureLightCleaner = { cleaner in
            cleaner.afterRecheck = { _ in try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: source.path) }
        }
        await world.quick.begin()
        let folder = world.main.appending(path: "node_modules")
        #expect(world.group(.projects).contains { world.matches($0.path, folder) })
        let task = try #require(world.quick.confirm())
        await world.app.cleanupQueue.waitUntilEmpty()
        #expect(world.exists(folder))
        #expect(task.items.first { $0.resources.contains(CanonicalPath.resolve(folder)) }?.result?.state == .refused)
    }

    @Test func dismissalDiscardsInFlightPreviewAndReopeningHasANewToken() async throws {
        let world = try await QuickCleanTestWorld.make()
        defer { world.remove() }
        let gate = QueueGate()
        world.quick.beforePublish = { await gate.wait() }
        let first = Task { await world.quick.begin() }
        #expect(await eventually { gate.entered })
        world.quick.dismiss()
        gate.open(); await first.value
        #expect(world.quick.preview == nil && !world.quick.canConfirm)
        #expect(world.quick.confirm() == nil && world.app.cleanupQueue.tasks.isEmpty)
        world.quick.beforePublish = {}
        await world.quick.begin()
        #expect(world.quick.preview != nil && world.quick.canConfirm)
    }

    @Test func queuedConflictRejectsWholePlanAndCancelRunsNothing() async throws {
        let world = try await QuickCleanTestWorld.make()
        defer { world.remove() }
        await world.quick.begin()
        let holder = try await QueueLockHolder.take(world.app)
        let blocking = try #require(world.app.cleanupQueue.enqueue(title: "Other", unit: "items", work: [queueWork(world.old.path)]))
        #expect(!world.quick.canConfirm && world.quick.confirm() == nil)
        #expect(world.app.cleanupQueue.tasks.count == 1)
        world.app.cleanupQueue.cancel(blocking)
        await holder.release()
        #expect(world.exists(world.old))
        await world.quick.begin()
        let secondHolder = try await QueueLockHolder.take(world.app)
        let task = try #require(world.quick.confirm())
        world.app.cleanupQueue.cancel(task)
        await secondHolder.release()
        await world.app.cleanupQueue.waitUntilEmpty()
        #expect(task.state == .cancelled && world.exists(world.old))
    }

    @Test func quittingInvalidatesConfirmation() async throws {
        let world = try await QuickCleanTestWorld.make()
        defer { world.remove() }
        await world.quick.begin()
        await world.app.prepareToQuit()
        #expect(!world.quick.canConfirm && world.quick.confirm() == nil)
        #expect(world.app.cleanupQueue.tasks.isEmpty && world.exists(world.old))
    }

    @Test(arguments: ["local commit", "stash", "ignored user file"])
    func automaticWorktreeProtectionsRemainConservative(_ protection: String) async throws {
        let world = try await QuickCleanTestWorld.make()
        defer { world.remove() }
        let aged = AgedRepos(fixture: world.fixture, now: world.now)
        if protection == "local commit" {
            try world.fixture.write("local work\n", to: "source.txt", in: world.old)
            try await aged.git(["commit", "--quiet", "-am", "Local only"], in: world.old, days: 8)
        } else if protection == "stash" {
            try world.fixture.write("stashed work\n", to: "source.txt", in: world.old)
            try await aged.git(["stash", "push", "--quiet"], in: world.old, days: 8)
        } else {
            try world.fixture.write(".env\nnode_modules/\n", to: ".gitignore", in: world.old)
            try await aged.git(["commit", "--quiet", "-am", "Ignore secret"], in: world.old, days: 8)
            try await aged.git(["push", "--quiet", "origin", "old-branch"], in: world.old, days: 8)
            try world.fixture.write("SECRET=fixture\n", to: ".env", in: world.old)
        }
        try await aged.age(world.old, days: 8)
        await world.quick.begin()
        #expect(world.group(.worktrees).allSatisfy { !world.matches($0.path, world.old) })
        #expect(world.exists(world.old))
    }

    @Test func claudeOptInIsKeptAndChangingItAfterPreviewRefusesRemoval() async throws {
        let world = try await QuickCleanTestWorld.make()
        defer { world.remove() }
        let aged = AgedRepos(fixture: world.fixture, now: world.now)
        let claude = world.main.appending(path: ".claude/worktrees/quick-session")
        try await aged.git(["worktree", "add", "--quiet", "-b", "claude-session", claude.path], in: world.main, days: 8)
        try await aged.age(claude, days: 8); try await aged.age(world.main, days: 8)
        await world.quick.begin()
        #expect(world.group(.worktrees).allSatisfy { !world.matches($0.path, claude) })
        let store = SettingsStore(environment: world.app.environment)
        try store.update { $0.includeClaudeInAuto = true }
        await world.quick.begin()
        #expect(world.group(.worktrees).contains { world.matches($0.path, claude) })
        #expect(world.quick.preview?.warnings.contains(SafetyReason.claudeSessionWarning) == true)
        try store.update { $0.includeClaudeInAuto = false }
        let task = try #require(world.quick.confirm())
        await world.app.cleanupQueue.waitUntilEmpty()
        #expect(world.exists(claude))
        #expect(task.items.first { $0.resources.contains(CanonicalPath.resolve(claude)) }?.result?.state == .refused)
    }

    @Test func cancellingThePreviewCallerCannotPublishOrLeaveTheSpinnerRunning() async throws {
        let world = try await QuickCleanTestWorld.make()
        defer { world.remove() }
        let gate = QueueGate()
        world.quick.beforePublish = { await gate.wait() }
        let preparing = Task { await world.quick.begin() }
        #expect(await eventually { gate.entered })
        preparing.cancel(); gate.open(); await preparing.value
        #expect(world.quick.preview == nil && !world.quick.isPreparing && !world.quick.canConfirm)
        #expect(world.app.cleanupQueue.tasks.isEmpty)
    }


    @Test(arguments: [false, true])
    func runtimePolicyRequiresSevenDaysEvenWhenClockMovesBackAndActivityIsUnchanged(_ project: Bool) async throws {
        let world = try await QuickCleanTestWorld.make()
        defer { world.remove() }
        await world.app.refresh()
        let worktree = try #require(world.app.scan?.worktrees.first { CanonicalPath.same($0.url, world.old) })
        let environment = world.app.environment
        let idle = await IdleClock(git: world.fixture.git, claudeConfigDirectory: environment.claudeConfigDirectory,
                                   now: environment.now).report(for: worktree)
        #expect(idle.idleDays == 8)
        var rolledBack = environment
        let earlier = world.now.addingTimeInterval(-3 * 86400)
        rolledBack.now = { earlier }
        let policy = QuickCleanRepositoryPolicy(git: world.fixture.git, environment: rolledBack, worktree: worktree,
                                               idle: idle, known: world.app.scan?.worktrees ?? [])
        #expect(await policy.reason(project: project) != nil)
    }

}
