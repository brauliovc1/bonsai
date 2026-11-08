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

        // idle-a gains an untracked file after planning: it no longer matches the plan, so it is refused and
        // stays; idle-b still goes.
        try world.fixture.write("late\n", to: "late.txt", in: paths[0])
        let runner = AutoRunner(remover: Remover(git: world.fixture.git, settings: settings, environment: environment))
        let outcome = await runner.run(plan, ignoringReportOnly: true)

        #expect(!outcome.reportOnly)
        #expect(outcome.removed.map(\.entry.branch) == ["idle-b"])
        #expect(outcome.removed.first?.entry.mode == .auto)
        #expect(outcome.refused.map(\.worktree.branch) == ["idle-a"])
        #expect(outcome.refused.first?.reason.hasPrefix("changed since the plan: New: ") == true, "\(outcome.refused)")
        #expect(outcome.failed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: paths[0].appending(path: "late.txt").path))
        #expect(!FileManager.default.fileExists(atPath: paths[1].path))
        #expect(FileManager.default.fileExists(atPath: paths[2].appending(path: "work.txt").path))

        let summary = outcome.summary(date: environment.now())
        #expect(summary.removedCount == 1 && summary.notifiedCount == 1 && summary.failures.isEmpty)
        #expect(summary.refused.count == 1 && summary.refused[0].contains("alpha-idle-a: changed since the plan"))
        #expect(summary.plannedCount == 2)
        #expect(try RemovalLog(environment: environment).entries().map(\.branch) == ["idle-b"])
    }

    /// The plan's verdict travels with each removal: a worktree whose branch moved after the plan (a new
    /// commit, pushed, so every safety rule still passes) is refused because HEAD is not what was planned.
    @Test func aCommitAfterThePlanIsRefusedEvenWhenItPassesTheRules() async throws {
        let (world, environment, paths) = try await world()
        defer { world.remove() }
        let settings = Settings(autoEnabled: true, autoEnabledAt: environment.now())
        let plan = try await plan(world, environment, settings: settings)

        try world.fixture.write("more\n", to: "more.txt", in: paths[0])
        try await world.fixture.commitAll(in: paths[0], message: "More")
        try await world.fixture.run(["push", "--quiet", "-u", "origin", "idle-a"], in: paths[0])
        let runner = AutoRunner(remover: Remover(git: world.fixture.git, settings: settings, environment: environment))
        let outcome = await runner.run(plan, ignoringReportOnly: true)

        #expect(outcome.refused.map(\.worktree.branch) == ["idle-a"])
        #expect(outcome.refused.first?.reason.contains("HEAD moved") == true, "\(outcome.refused)")
        #expect(FileManager.default.fileExists(atPath: paths[0].appending(path: "more.txt").path))
        #expect(outcome.removed.map(\.entry.branch) == ["idle-b"])
    }

    /// Once `stopReason` gives a reason, nothing more is removed and the rest are reported as stopped.
    @Test func aStoppedRunRemovesNothingMore() async throws {
        let (world, environment, paths) = try await world()
        defer { world.remove() }
        let settings = Settings(autoEnabled: true, autoEnabledAt: environment.now())
        let plan = try await plan(world, environment, settings: settings)
        let runner = AutoRunner(remover: Remover(git: world.fixture.git, settings: settings, environment: environment))

        let asked = Counter()
        let outcome = await runner.run(plan, ignoringReportOnly: true) { asked.next() < 2 ? nil : .turnedOff }

        #expect(outcome.removed.map(\.entry.branch) == ["idle-a"])
        #expect(outcome.refused.isEmpty)
        #expect(outcome.stopped == .turnedOff && outcome.stoppedWorktrees.map(\.branch) == ["idle-b"])
        #expect(FileManager.default.fileExists(atPath: paths[1].path))
        #expect(asked.value == 3, "asked before each removal and again right before its git")
        let summary = outcome.summary(date: environment.now())
        #expect(summary.stopReason == .turnedOff && summary.stoppedCount == 1)
    }

    /// The last ask is inside `Remover`, after its re-check and the process index, right before git: a stop
    /// there leaves the worktree untouched and logs nothing.
    @Test func aStopRightBeforeGitLeavesTheWorktreeAlone() async throws {
        let (world, environment, paths) = try await world()
        defer { world.remove() }
        let settings = Settings(autoEnabled: true, autoEnabledAt: environment.now())
        let plan = try await plan(world, environment, settings: settings)
        let runner = AutoRunner(remover: Remover(git: world.fixture.git, settings: settings, environment: environment))

        let asked = Counter()
        let outcome = await runner.run(plan, ignoringReportOnly: true) { asked.next() == 0 ? nil : .rulesChanged }

        #expect(outcome.removed.isEmpty && outcome.refused.isEmpty && outcome.failed.isEmpty)
        #expect(outcome.stopped == .rulesChanged && outcome.stoppedWorktrees.map(\.branch) == ["idle-a", "idle-b"])
        #expect(paths.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(!FileManager.default.fileExists(atPath: RemovalLog(environment: environment).fileURL.path))
    }

    @Test func reportOnlyNeverAsksTheRemover() async throws {
        let (world, environment, paths) = try await world()
        defer { world.remove() }
        let settings = Settings(autoEnabled: true, autoEnabledAt: environment.now())
        let plan = try await plan(world, environment, settings: settings)
        let runner = AutoRunner(remover: Remover(git: world.fixture.git, settings: settings, environment: environment))

        let asked = Counter()
        let outcome = await runner.run(plan) { _ = asked.next(); return nil }
        #expect(outcome.reportOnly && outcome.planned == 2 && outcome.estimatedBytes == plan.estimatedBytes)
        #expect(asked.value == 0)
        #expect(paths.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(!FileManager.default.fileExists(atPath: RemovalLog(environment: environment).fileURL.path))
    }
}

/// Counts calls from any task.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    /// The number of earlier calls.
    func next() -> Int {
        lock.withLock {
            defer { count += 1 }
            return count
        }
    }
}
