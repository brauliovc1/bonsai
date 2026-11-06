@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Idle clock (§4.3)")
struct IdleClockTests {
    private let day: TimeInterval = 86_400

    /// A worktree whose files and git dir are all 100 days older than HEAD's commit.
    private func agedWorktree(_ world: SafetyWorld) async throws -> (url: URL, commit: Date, gitDir: URL) {
        let wt = try await world.sibling("aged")
        let seconds = try await world.fixture.run(["log", "-1", "--format=%ct"], in: wt)
        let commit = Date(timeIntervalSince1970: try #require(TimeInterval(seconds)))
        let gitDir = URL(fileURLWithPath: try await world.fixture.run(["rev-parse", "--git-dir"], in: wt))
        let old = commit.addingTimeInterval(-100 * day)
        try world.fixture.setModificationDate(old, of: wt, recursively: true)
        for name in ["index", "HEAD", "logs/HEAD"] {
            try world.fixture.setModificationDate(old, of: gitDir.appending(path: name))
        }
        return (wt, commit, gitDir)
    }

    private func clock(_ world: SafetyWorld, now: Date, maxEntries: Int = 20_000) -> IdleClock {
        IdleClock(
            git: world.fixture.git,
            claudeConfigDirectory: world.fixture.environment().claudeConfigDirectory,
            maxEntries: maxEntries,
            now: { now }
        )
    }

    @Test func eachSignalCanBeTheNewest() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let (wt, commit, gitDir) = try await agedWorktree(world)
        let worktree = try await world.worktree(wt)
        let now = commit.addingTimeInterval(40 * day)
        let idleClock = clock(world, now: now)

        var report = await idleClock.report(for: worktree)
        #expect(report.errors.isEmpty, "\(report.errors)")
        #expect(report.newestSignal == .headCommit)
        #expect(report.idleDays == 40)
        #expect(Set(report.signals.keys) == [.headCommit, .gitActivity, .fileChange])

        try world.fixture.setModificationDate(commit.addingTimeInterval(5 * day), of: gitDir.appending(path: "index"))
        report = await idleClock.report(for: worktree)
        #expect(report.newestSignal == .gitActivity)
        #expect(report.idleDays == 35)

        try world.fixture.setModificationDate(commit.addingTimeInterval(10 * day), of: wt.appending(path: "README.md"))
        report = await idleClock.report(for: worktree)
        #expect(report.newestSignal == .fileChange)
        #expect(report.idleDays == 30)

        let transcripts = world.fixture.environment().claudeConfigDirectory
            .appending(path: "projects/\(ClaudeTranscriptLocator.encode(worktree.path))")
        let transcript = try world.fixture.write("{}\n", to: "session.jsonl", in: transcripts)
        try world.fixture.setModificationDate(commit.addingTimeInterval(20 * day) + 3600, of: transcript)
        report = await idleClock.report(for: worktree)
        #expect(report.newestSignal == .claudeTranscript)
        #expect(report.idleDays == 19)
        #expect(report.signals.count == 4)
    }

    @Test func dependencyAndNestedFoldersDontCount() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let (wt, commit, _) = try await agedWorktree(world)
        let worktree = try await world.worktree(wt)
        let fresh = commit.addingTimeInterval(30 * day)
        for path in ["node_modules/pkg/index.js", "packages/web/.next/cache.bin", "build/out.o", "vendor/repo/x.txt"] {
            try world.fixture.setModificationDate(fresh, of: try world.fixture.write("x\n", to: path, in: wt))
        }
        try world.fixture.write("gitdir: elsewhere\n", to: "vendor/repo/.git", in: wt)

        let report = await clock(world, now: commit.addingTimeInterval(40 * day)).report(for: worktree)
        #expect(report.newestSignal == .headCommit)
        #expect(report.idleDays == 40)
    }

    @Test func capHitMakesIdleUnknownAndSkipsAuto() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let (wt, commit, _) = try await agedWorktree(world)
        for index in 0..<12 {
            try world.fixture.write("\(index)\n", to: "data/file\(index).txt", in: wt)
        }
        try await world.fixture.commitAll(in: wt)
        try await world.fixture.run(["push", "--quiet", "-u", "origin", "aged"], in: wt)
        let worktree = try await world.worktree(wt)

        let report = await clock(world, now: commit.addingTimeInterval(400 * day), maxEntries: 5).report(for: worktree)
        #expect(report.capHit)
        #expect(report.idleDays == nil)

        let safety = try await world.check(wt, idle: report)
        #expect(safety.notes == [.idleUnknown])
        #expect(safety.manualAllowed && !safety.autoEligible)
        let row = WorktreeAssessment(worktree: worktree, idle: report, safety: safety)
        let plan = AutoPlanner.plan([row], settings: Settings(), now: commit)
        #expect(plan.remove.isEmpty && plan.notifyLocalWork.isEmpty)
        #expect(plan.skipped.map(\.reason) == [.idleUnknown])
    }

    @Test func transcriptFolderIsFoundForPathsWithSlashesAndDots() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        #expect(ClaudeTranscriptLocator.encode("/Users/a/my.repo/.claude/worktrees/x_y")
            == "-Users-a-my-repo--claude-worktrees-x-y")

        let wt = try await world.fixture.addClaudeWorktree(to: world.repo, name: "fix.v2")
        #expect(wt.path.contains("/.claude/") && wt.path.contains("fix.v2"))
        let locator = ClaudeTranscriptLocator(claudeConfigDirectory: world.fixture.environment().claudeConfigDirectory)
        #expect(locator.newestTranscriptDate(for: wt) == nil)

        // Written under the symlink-resolved spelling (/private/var/...), found from the plain one.
        let folder = locator.projectsDirectory.appending(path: ClaudeTranscriptLocator.encode(CanonicalPath.resolve(wt)))
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        try world.fixture.setModificationDate(date, of: try world.fixture.write("{}\n", to: "a.jsonl", in: folder))
        try world.fixture.setModificationDate(date + 99, of: try world.fixture.write("x\n", to: "notes.txt", in: folder))
        #expect(locator.transcriptFolders(for: wt).count == 1)
        #expect(locator.newestTranscriptDate(for: wt) == date)
    }

    @Test func missingFolderIsIdleUnknown() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("gone")
        let worktree = try await world.worktree(wt)
        try world.fixture.deleteFolder(wt)
        let report = await clock(world, now: Date()).report(for: worktree)
        #expect(report.idleDays == nil)
        #expect(!report.errors.isEmpty)
    }
}
