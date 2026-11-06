@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Idle clock (§4.3)")
struct IdleClockTests {
    private let day: TimeInterval = 86_400

    /// A worktree whose files, git dir and reflog entries are all 100 days older than HEAD's commit.
    private func agedWorktree(_ world: SafetyWorld, name: String = "aged") async throws -> (url: URL, commit: Date, gitDir: URL) {
        let wt = try await world.sibling(name)
        let seconds = try await world.fixture.run(["log", "-1", "--format=%ct"], in: wt)
        let commit = Date(timeIntervalSince1970: try #require(TimeInterval(seconds)))
        let gitDir = URL(fileURLWithPath: try await world.fixture.run(["rev-parse", "--absolute-git-dir"], in: wt))
        let old = commit.addingTimeInterval(-100 * day)
        try world.fixture.setModificationDate(old, of: wt, recursively: true)
        try setReflogDates(old, in: gitDir)
        for name in ["index", "HEAD", "logs/HEAD"] {
            try world.fixture.setModificationDate(old, of: gitDir.appending(path: name))
        }
        return (wt, commit, gitDir)
    }

    /// Rewrites the timestamp of every `logs/HEAD` entry (`... <seconds> <zone>\t<message>`).
    private func setReflogDates(_ date: Date, in gitDir: URL, lastOnly: Bool = false) throws {
        let file = gitDir.appending(path: "logs/HEAD")
        var lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map(String.init)
        for index in lines.indices where !lastOnly || index == lines.count - 1 {
            let parts = lines[index].split(separator: "\t", maxSplits: 1).map(String.init)
            var words = parts[0].split(separator: " ").map(String.init)
            words[words.count - 2] = String(Int(date.timeIntervalSince1970))
            lines[index] = ([words.joined(separator: " ")] + parts.dropFirst()).joined(separator: "\t")
        }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
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
            .appending(path: "projects/\(TranscriptFolderEncoding.encode(worktree.path))")
        let transcript = try world.fixture.write("{}\n", to: "session.jsonl", in: transcripts)
        try world.fixture.setModificationDate(commit.addingTimeInterval(20 * day) + 3600, of: transcript)
        report = await idleClock.report(for: worktree)
        #expect(report.newestSignal == .claudeTranscript)
        #expect(report.idleDays == 19)
        #expect(report.signals.count == 4)
    }

    /// Also `.DS_Store`: Finder rewrites it when someone only looks at the folder (Nexus-a13 on 11-06).
    @Test func dependencyAndNestedFoldersDontCount() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let (wt, commit, _) = try await agedWorktree(world)
        let worktree = try await world.worktree(wt)
        let fresh = commit.addingTimeInterval(30 * day)
        for path in ["node_modules/pkg/index.js", "packages/web/.next/cache.bin", "build/out.o", "vendor/repo/x.txt",
                     ".DS_Store", "src/.DS_Store"] {
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
        #expect(TranscriptFolderEncoding.encode("/Users/a/my.repo/.claude/worktrees/x_y")
            == "-Users-a-my-repo--claude-worktrees-x-y")

        let wt = try await world.fixture.addClaudeWorktree(to: world.repo, name: "fix.v2")
        let worktree = try await world.worktree(wt)
        #expect(wt.path.contains("/.claude/") && wt.path.contains("fix.v2"))
        let locator = ClaudeTranscriptLocator(claudeConfigDirectory: world.fixture.environment().claudeConfigDirectory)
        #expect(locator.lookup(for: worktree.path) == .absent)

        // Written under the symlink-resolved spelling (/private/var/...), found from the plain one.
        let folder = locator.projectsDirectory.appending(path: TranscriptFolderEncoding.encode(CanonicalPath.resolve(wt)))
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        try world.fixture.setModificationDate(date, of: try world.fixture.write("{}\n", to: "a.jsonl", in: folder))
        try world.fixture.setModificationDate(date + 99, of: try world.fixture.write("x\n", to: "notes.txt", in: folder))
        #expect(locator.transcriptFolders(for: wt.path).count == 1)
        #expect(locator.lookup(for: wt.path) == .newest(date))
    }

    // Item 9: Claude Code replaces UTF-16 code units, so an emoji becomes "--".
    @Test func transcriptEncodingWorksOnUTF16CodeUnits() async throws {
        #expect(TranscriptFolderEncoding.encode("/a/wt \u{1F680} caf\u{E9}") == "-a-wt----caf-")
        #expect(TranscriptFolderEncoding.encode("/a/caf\u{65}\u{301}") == "-a-cafe-")

        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addClaudeWorktree(to: world.repo, name: "rocket-\u{1F680}")
        let worktree = try await world.worktree(wt)
        let locator = ClaudeTranscriptLocator(claudeConfigDirectory: world.fixture.environment().claudeConfigDirectory)
        let encoded = TranscriptFolderEncoding.encode(worktree.path)
        #expect(encoded.hasSuffix("-rocket---"))
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let folder = locator.projectsDirectory.appending(path: encoded)
        try world.fixture.setModificationDate(date, of: try world.fixture.write("{}\n", to: "s.jsonl", in: folder))
        #expect(locator.lookup(for: worktree.path) == .newest(date))
    }

    // Item 9: a transcript folder that exists but can't be read makes idle unknown.
    @Test func unreadableTranscriptFolderIsIdleUnknown() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let (wt, commit, _) = try await agedWorktree(world)
        let worktree = try await world.worktree(wt)
        let folder = world.fixture.environment().claudeConfigDirectory
            .appending(path: "projects/\(TranscriptFolderEncoding.encode(worktree.path))")
        try world.fixture.write("{}\n", to: "s.jsonl", in: folder)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }

        let report = await clock(world, now: commit.addingTimeInterval(40 * day)).report(for: worktree)
        #expect(report.idleDays == nil)
        #expect(report.errors.contains { $0.hasPrefix("Claude transcripts") }, "\(report.errors)")
    }

    // Item 6: git gc rewrites logs/HEAD (new mtime, old entries); only the last entry's time counts.
    @Test func reflogEntryTimeCountsNotTheFileModificationTime() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let (wt, commit, gitDir) = try await agedWorktree(world)
        let worktree = try await world.worktree(wt)
        let idleClock = clock(world, now: commit.addingTimeInterval(40 * day))
        let reflog = gitDir.appending(path: "logs/HEAD")

        try world.fixture.setModificationDate(commit.addingTimeInterval(39 * day), of: reflog)
        var report = await idleClock.report(for: worktree)
        #expect(report.newestSignal == .headCommit)
        #expect(report.idleDays == 40)

        try setReflogDates(commit.addingTimeInterval(5 * day), in: gitDir, lastOnly: true)
        report = await idleClock.report(for: worktree)
        #expect(report.newestSignal == .gitActivity)
        #expect(report.idleDays == 35)

        // Emptied by gc: no reflog signal, the index and HEAD mtimes still count.
        try Data().write(to: reflog)
        #expect(try IdleClock.lastReflogDate(reflog) == nil)
        report = await idleClock.report(for: worktree)
        #expect(report.errors.isEmpty, "\(report.errors)")
        #expect(report.newestSignal == .headCommit)
        #expect(report.idleDays == 40)
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
