@testable import CleanCore
import Foundation
import Testing

@Suite("Removal expectation")
struct RemovalExpectationTests {
    private let then = Date(timeIntervalSince1970: 1_700_000_000)

    private func worktree(branch: String? = "task", head: String = "aaaa1111", kind: WorktreeKind = .sibling) -> Worktree {
        Worktree(path: "/tmp/w/repo-task", repoPath: "/tmp/w/repo", head: head, branch: branch, isMain: false, kind: kind)
    }

    private func report(_ notes: [SafetyReason], blockers: [SafetyReason] = []) -> SafetyReport {
        SafetyReport(blockers: blockers, notes: notes, autoBlockers: blockers + notes)
    }

    private func idle(newest: Date, days: Int) -> IdleReport {
        IdleReport(newest: newest, idleDays: days, signals: [.fileChange: newest])
    }

    private func expectation(_ notes: [SafetyReason], days: Int = 10) -> RemovalExpectation {
        RemovalExpectation(assessment: WorktreeAssessment(
            worktree: worktree(),
            idle: idle(newest: then, days: days),
            safety: report(notes + [.recentlyActive(days: days)])
        ))
    }

    @Test func timePassingAloneIsNoChange() {
        let confirmed = expectation([])
        let changes = confirmed.changes(
            fresh: worktree(),
            safety: report([.recentlyActive(days: 11)]),
            idle: idle(newest: then, days: 11)
        )
        #expect(changes.isEmpty, "\(changes)")
    }

    @Test func newerActivityIsAChange() {
        let changes = expectation([]).changes(
            fresh: worktree(),
            safety: report([.recentlyActive(days: 0)]),
            idle: idle(newest: then.addingTimeInterval(60), days: 0)
        )
        #expect(changes == ["It was used since (file change)."])
    }

    @Test(arguments: [
        ([SafetyReason.ignoredUserFiles([".env"])], [SafetyReason.ignoredUserFiles([".env", "secrets.json"])]),
        ([.localOnlyCommits(count: 1, onBranch: true)], [.localOnlyCommits(count: 2, onBranch: true)]),
        ([.stash(count: 1)], [.stash(count: 2)]),
        ([.nestedClones([".build/checkouts/a"])], [.nestedClones([".build/checkouts/a", ".build/checkouts/b"])]),
        ([], [.claudeSession]),
    ])
    func notesCompareExactly(confirmed: [SafetyReason], fresh: [SafetyReason]) {
        let changes = expectation(confirmed).changes(
            fresh: worktree(),
            safety: report(fresh + [.recentlyActive(days: 10)]),
            idle: idle(newest: then, days: 10)
        )
        #expect(changes.count == 1, "\(changes)")
        #expect(changes.first?.hasPrefix("New: ") == true)
    }

    @Test func aNewBlockerIsAChange() {
        let changes = expectation([]).changes(
            fresh: worktree(),
            safety: report([.recentlyActive(days: 10)], blockers: [.uncommitted(count: 1)]),
            idle: idle(newest: then, days: 10)
        )
        #expect(changes == ["New: " + SafetyReason.uncommitted(count: 1).sentence])
    }

    @Test func anotherBranchHeadOrKindIsAChange() {
        let same = report([.recentlyActive(days: 10)])
        let quiet = idle(newest: then, days: 10)
        let confirmed = expectation([])
        #expect(confirmed.changes(fresh: worktree(branch: "other"), safety: same, idle: quiet)
            == ["The branch is now other (was task)."])
        #expect(confirmed.changes(fresh: worktree(branch: nil), safety: same, idle: quiet)
            == ["The branch is now detached (was task)."])
        #expect(confirmed.changes(fresh: worktree(head: "bbbb2222"), safety: same, idle: quiet)
            == ["HEAD moved from aaaa1111 to bbbb2222."])
        #expect(confirmed.changes(fresh: worktree(kind: .claude), safety: same, idle: quiet)
            == ["Its kind is now claude (was sibling)."])
        #expect(confirmed.changes(fresh: worktree(), safety: same, idle: quiet).isEmpty)
    }
}
