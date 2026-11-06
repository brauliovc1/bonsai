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
        #expect(!report.manualAllowed)
        #expect(!report.autoEligible)
        let message = report.blockers.compactMap { reason -> String? in
            if case .gitError(let message) = reason { return message }
            return nil
        }.first
        #expect(message?.contains("stale") == true, "\(report.blockers)")
        #expect(message?.contains(alpha.lastPathComponent) == true)

        let real = try await fixture.worktree(at: shared, in: bravo)
        let realReport = await check.check(real, idle: .idle(days: 40), settings: Settings(), cwdIndex: ProcessCwdIndex(entries: []))
        #expect(realReport.manualAllowed, "\(realReport.blockers)")
    }
}
