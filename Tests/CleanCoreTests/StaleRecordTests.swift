@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Stale worktree records")
struct StaleRecordTests {
    /// Repo alpha still lists a folder that is now repo bravo's worktree. alpha's record must block both
    /// modes: every git fact read in the folder describes bravo's worktree.
    @Test func aRecordWhoseFolderBelongsToAnotherRepoIsBlocked() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let alpha = try await fixture.makeRepo("alpha")
        let bravo = try await fixture.makeRepo("bravo")
        let shared = fixture.scanRoot.appending(path: "shared", directoryHint: .isDirectory)
        try await fixture.addWorktree(to: alpha, at: shared, branch: "a-task")
        try FileManager.default.removeItem(at: shared)
        try await fixture.addWorktree(to: bravo, at: shared, branch: "b-task")
        let check = SafetyCheck(git: fixture.git)

        let stale = try await fixture.worktree(at: shared, in: alpha)
        #expect(!stale.isPrunable, "git doesn't see it: the folder exists")
        let report = await check.check(stale, idle: .idle(days: 40), settings: Settings(), cwdIndex: ProcessCwdIndex(entries: []))
        // Both modes are blocked, by a reason of its own (not "git error").
        #expect(!report.manualAllowed)
        #expect(!report.autoEligible)
        let leadsTo = report.blockers.compactMap { reason -> String? in
            if case .staleRecord(let leadsTo) = reason { return leadsTo }
            return nil
        }.first
        #expect(leadsTo?.contains("bravo") == true, "\(report.blockers)")
        #expect(!report.blockers.contains { if case .gitError = $0 { true } else { false } }, "\(report.blockers)")
        #expect(report.autoBlockers.contains { if case .staleRecord = $0 { true } else { false } })
        #expect(report.status.label == "BLOCKED: stale record")
        let reason = try #require(report.blockers.first)
        #expect(reason.label == "stale record")
        #expect(reason.sentence.contains("another repo's folder"))
        #expect(reason.sentence.contains(leadsTo ?? "?"))

        let real = try await fixture.worktree(at: shared, in: bravo)
        let realReport = await check.check(real, idle: .idle(days: 40), settings: Settings(), cwdIndex: ProcessCwdIndex(entries: []))
        #expect(realReport.manualAllowed, "\(realReport.blockers)")
    }
}

@Suite("Stale records and auto mode")
struct StaleRecordAutoTests {
    /// Idle for 40 days and nothing else wrong: a stale record is still never removed, and never reported
    /// as "kept only because of local work" either.
    @Test func autoModeNeitherRemovesNorNotifiesForAStaleRecord() {
        let worktree = Worktree(path: "/tmp/shared", repoPath: "/tmp/alpha", head: "abc", branch: "a-task", isMain: false, kind: .sibling)
        let state = WorktreeState(staleRecord: "/tmp/bravo/.git/worktrees/shared")
        let safety = SafetyCheck.evaluate(
            worktree: worktree, state: state, idle: .idle(days: 40), settings: Settings(),
            cwdIndex: ProcessCwdIndex(entries: [])
        )
        #expect(!safety.manualAllowed && !safety.autoEligible)
        let assessment = WorktreeAssessment(worktree: worktree, idle: .idle(days: 40), safety: safety)
        let plan = AutoPlanner.plan([assessment], settings: Settings(), now: Date())
        #expect(plan.remove.isEmpty)
        #expect(plan.notifyLocalWork.isEmpty)
        #expect(plan.skipped.count == 1)
    }
}
