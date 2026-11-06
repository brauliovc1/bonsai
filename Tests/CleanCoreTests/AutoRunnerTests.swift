@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("AutoRunner")
struct AutoRunnerTests {
    /// Clean `idle-a` and `idle-b`, dirty `dirty`; the clock runs 40 days ahead so all are idle.
    private func world() async throws -> (SafetyWorld, CleanEnvironment, [URL]) {
        let world = try await SafetyWorld.make()
        let a = try await world.sibling("idle-a")
        let b = try await world.sibling("idle-b")
        let dirty = try await world.sibling("dirty")
        try world.fixture.write("work\n", to: "work.txt", in: dirty)
        return (world, world.fixture.environment(clockOffset: 40 * 86_400), [a, b, dirty])
    }

    private func plan(_ world: SafetyWorld, _ environment: CleanEnvironment, settings: Settings) async throws -> AutoPlan {
        let worktrees = try await WorktreeScanner(git: world.fixture.git, cursorWorktreesDirectory: environment.cursorWorktreesDirectory)
            .worktrees(in: world.repo)
        let assessor = WorktreeAssessor(git: world.fixture.git, settings: settings, environment: environment)
        let rows = await assessor.assess(worktrees, cwdIndex: ProcessCwdIndex(entries: []))
        return AutoPlanner.plan(rows, settings: settings, now: environment.now())
    }

    @Test func reportOnlyRemovesNothing() async throws {
        let (world, environment, paths) = try await world()
        defer { world.remove() }
        let settings = Settings(autoEnabled: true, autoEnabledAt: environment.now())
        let plan = try await plan(world, environment, settings: settings)
        #expect(plan.reportOnly)
        #expect(plan.remove.map(\.worktree.branch) == ["idle-a", "idle-b"])
        #expect(plan.notifyLocalWork.map(\.worktree.branch) == ["dirty"])

        let runner = AutoRunner(remover: Remover(git: world.fixture.git, settings: settings, environment: environment))
        let outcome = await runner.run(plan)
        #expect(outcome.reportOnly && outcome.removed.isEmpty && outcome.failed.isEmpty)
        #expect(outcome.notified.count == 1)
        #expect(paths.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(outcome.summary(date: environment.now()).reportOnly)
    }

    @Test func runsOneAtATimeAndContinuesAfterAFailure() async throws {
        let (world, environment, paths) = try await world()
        defer { world.remove() }
        let settings = Settings(autoEnabled: true, autoEnabledAt: environment.now())
        let plan = try await plan(world, environment, settings: settings)

        // idle-a gains a file after planning: its re-check fails, idle-b still goes.
        try world.fixture.write("late\n", to: "late.txt", in: paths[0])
        let runner = AutoRunner(remover: Remover(git: world.fixture.git, settings: settings, environment: environment))
        let outcome = await runner.run(plan, ignoringReportOnly: true)

        #expect(!outcome.reportOnly)
        #expect(outcome.removed.map(\.entry.branch) == ["idle-b"])
        #expect(outcome.removed.first?.entry.mode == .auto)
        #expect(outcome.failed.map(\.worktree.branch) == ["idle-a"])
        #expect(FileManager.default.fileExists(atPath: paths[0].appending(path: "late.txt").path))
        #expect(!FileManager.default.fileExists(atPath: paths[1].path))
        #expect(FileManager.default.fileExists(atPath: paths[2].appending(path: "work.txt").path))

        let summary = outcome.summary(date: environment.now())
        #expect(summary.removedCount == 1 && summary.notifiedCount == 1 && summary.failures.count == 1)
        #expect(try RemovalLog(environment: environment).entries().map(\.branch) == ["idle-b"])
    }
}
