@testable import CleanCore
import Foundation
import Testing

/// Pure planner tests over made-up rows (no folders are read or written).
@Suite("AutoPlanner")
struct AutoPlannerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func row(
        _ name: String,
        kind: WorktreeKind = .sibling,
        isMain: Bool = false,
        idleDays: Int?,
        state: WorktreeState = WorktreeState(),
        settings: Settings = Settings(),
        locked: Bool = false
    ) -> WorktreeAssessment {
        let worktree = Worktree(
            path: "/nonexistent/bonsai-plan/\(name)",
            repoPath: "/nonexistent/bonsai-plan/repo",
            head: "0123456789abcdef",
            branch: name,
            isMain: isMain,
            lockedReason: locked ? "" : nil,
            kind: isMain ? .main : kind
        )
        let idle = idleDays.map { IdleReport.idle(days: $0, now: now) } ?? .unknown
        let safety = SafetyCheck.evaluate(
            worktree: worktree,
            state: state,
            idle: idle,
            settings: settings,
            cwdIndex: ProcessCwdIndex(entries: [])
        )
        return WorktreeAssessment(worktree: worktree, idle: idle, safety: safety, estimatedBytes: 1_000)
    }

    private func names(_ rows: [WorktreeAssessment]) -> [String] {
        rows.map(\.worktree.branch!)
    }

    @Test func thresholdBoundary() {
        let rows = [row("d29", idleDays: 29), row("d30", idleDays: 30), row("d31", idleDays: 31)]
        let plan = AutoPlanner.plan(rows, settings: Settings(), now: now)
        #expect(names(plan.remove) == ["d30", "d31"])
        #expect(plan.skipped.map(\.reason) == [.recentlyActive(days: 29)])
        #expect(plan.estimatedBytes == 2_000)
    }

    @Test func plannerRechecksTheThresholdItWasGiven() {
        // Assessed with a 30-day threshold, planned with 45: not removed.
        let plan = AutoPlanner.plan([row("d31", idleDays: 31)], settings: Settings(idleThresholdDays: 45), now: now)
        #expect(plan.remove.isEmpty)
        #expect(plan.skipped.count == 1)
    }

    @Test func reportOnlyBoundary() {
        let enabledAt = now.addingTimeInterval(-7 * day)
        var settings = Settings(autoEnabled: true, autoEnabledAt: enabledAt)
        #expect(!AutoPlanner.plan([], settings: settings, now: now).reportOnly)
        #expect(AutoPlanner.plan([], settings: settings, now: now.addingTimeInterval(-1)).reportOnly)
        #expect(AutoPlanner.plan([], settings: settings, now: now).reportOnlyEndsAt == now)

        settings.autoEnabledAt = nil
        #expect(AutoPlanner.plan([], settings: settings, now: now).reportOnly)
        settings.reportOnlyDays = 0
        settings.autoEnabledAt = now
        #expect(!AutoPlanner.plan([], settings: settings, now: now).reportOnly)
    }

    @Test func claudeWorktreesOnlyWhenIncluded() {
        let off = Settings()
        let offPlan = AutoPlanner.plan([row("c", kind: .claude, idleDays: 60, settings: off)], settings: off, now: now)
        #expect(offPlan.remove.isEmpty)
        #expect(offPlan.skipped.map(\.reason) == [.claudeSession])

        // A Claude worktree with local work is skipped too, not notified, while the setting is off.
        let dirty = WorktreeState(changedFiles: 3)
        let dirtyPlan = AutoPlanner.plan([row("cd", kind: .claude, idleDays: 60, state: dirty, settings: off)], settings: off, now: now)
        #expect(dirtyPlan.notifyLocalWork.isEmpty && dirtyPlan.skipped.count == 1)

        let on = Settings(includeClaudeInAuto: true)
        let onPlan = AutoPlanner.plan([row("c", kind: .claude, idleDays: 60, settings: on)], settings: on, now: now)
        #expect(names(onPlan.remove) == ["c"])
    }

    @Test func localWorkIsNotifiedOtherBlockersAreSkipped() {
        let rows = [
            row("dirty", idleDays: 40, state: WorktreeState(changedFiles: 31)),
            row("ahead", idleDays: 40, state: WorktreeState(localOnlyCommits: 2)),
            row("stash", idleDays: 40, state: WorktreeState(branchStashes: 1)),
            row("env", idleDays: 40, state: WorktreeState(ignoredUserFiles: [".env"])),
            row("recent-dirty", idleDays: 3, state: WorktreeState(changedFiles: 1)),
            row("locked-dirty", idleDays: 40, state: WorktreeState(changedFiles: 1), locked: true),
            row("subs", idleDays: 40, state: WorktreeState(hasSubmodules: true)),
            row("broken", idleDays: 40, state: WorktreeState(gitErrors: ["boom"])),
            row("unknown", idleDays: nil),
            row("clean", idleDays: 40),
        ]
        let plan = AutoPlanner.plan(rows, settings: Settings(), now: now)
        #expect(names(plan.remove) == ["clean"])
        #expect(names(plan.notifyLocalWork) == ["dirty", "ahead", "stash", "env"])
        #expect(plan.skipped.map(\.row.worktree.branch!) == ["recent-dirty", "locked-dirty", "subs", "broken", "unknown"])
        #expect(plan.skipped.map(\.reason) == [
            .uncommitted(count: 1), .locked(reason: ""), .submodules, .gitError("boom"), .idleUnknown,
        ])
        for removed in plan.remove {
            let hasLocalWork = removed.safety.autoBlockers.contains { $0.isLocalWork }
            #expect(!hasLocalWork)
        }
    }

    @Test func mainCheckoutNeverAppears() {
        let rows = [row("main", isMain: true, idleDays: 400), row("clean", idleDays: 40)]
        let plan = AutoPlanner.plan(rows, settings: Settings(), now: now)
        let all = plan.remove + plan.notifyLocalWork + plan.skipped.map(\.row)
        #expect(all.map(\.worktree.isMain) == [false])
    }
}
