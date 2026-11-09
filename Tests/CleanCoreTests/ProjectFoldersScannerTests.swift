@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Project folders scanner")
struct ProjectFoldersScannerTests {
    static let gitignore = "node_modules/\n.next/\nbuild/\n/.claude/worktrees/\n"

    /// Scans the fixture's root the way the CLI does: a scan, then the projects scanner over its worktrees.
    private func report(
        _ fixture: GitFixture,
        cwdIndex: ProcessCwdIndex = ProcessCwdIndex(entries: []),
        configure: (inout ProjectFoldersScanner) -> Void = { _ in }
    ) async -> ProjectFoldersReport {
        let environment = fixture.environment()
        let scan = await Scanner(environment: environment).scan(roots: [fixture.scanRoot], includeSizes: false)
        var scanner = ProjectFoldersScanner(git: fixture.git, environment: environment)
        configure(&scanner)
        return await scanner.scan(scan.worktrees, knownWorktrees: scan.worktrees, cwdIndex: cwdIndex)
    }

    @Test func anIdleCheckoutIsListedWithItsFoldersTotalAndRebuildLines() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let aged = AgedRepos(fixture: fixture)
        let shop = try await aged.repo("shop", days: 40, gitignore: Self.gitignore, files: [
            "package.json": "{}\n", "package-lock.json": "{}\n", "next.config.js": "module.exports = {}\n",
        ])
        try aged.blob(in: shop, "node_modules/react/index.bin", kibibytes: 64)
        try aged.blob(in: shop, ".next/cache/page.bin", kibibytes: 32)
        try await aged.age(shop, days: 40)

        let report = await report(fixture)

        #expect(report.projects.count == 1)
        let project = try #require(report.projects.first)
        #expect(project.worktree.kind == .main)
        #expect(project.idleDays == 40)
        #expect(project.folders.map(\.relativePath) == [".next", "node_modules"])
        let sizes = project.folders.compactMap(\.bytes)
        #expect(sizes.count == 2 && sizes.allSatisfy { $0 > 0 })
        #expect(project.totalBytes == sizes.reduce(0, +))
        #expect(project.totalBytes >= 96 * 1024)
        #expect(project.rebuildLines == ["npm install", ".next comes back with next build or next dev"])
        #expect(project.blocker == nil)
        #expect(project.status(threshold: 30) == .ready)
        #expect(report.ready(idleAtLeast: 30).map(\.id) == [project.id])
        #expect(report.idleTotal(atLeast: 30) == .init(count: 1, bytes: project.totalBytes))
        #expect(report.all == .init(count: 1, bytes: project.totalBytes))
        #expect(report.idleTotal(atLeast: 41).count == 0, "below a higher threshold it isn't idle")
        // Looking deletes nothing, and the CLI's scanner (no cache) writes nothing.
        #expect(FileManager.default.fileExists(atPath: shop.appending(path: "node_modules/react/index.bin").path))
        let cache = fixture.environment().settingsDirectory.appending(path: FolderSizeCache.fileName)
        #expect(!FileManager.default.fileExists(atPath: cache.path))
    }

    @Test func aRecentCheckoutIsListedButNotReadyAndBiggestComesFirst() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let aged = AgedRepos(fixture: fixture)
        let old = try await aged.repo("old", days: 50, gitignore: Self.gitignore)
        try aged.blob(in: old, "node_modules/a.bin", kibibytes: 16)
        try await aged.age(old, days: 50)
        let fresh = try await aged.repo("fresh", days: 3, gitignore: Self.gitignore)
        try aged.blob(in: fresh, "node_modules/a.bin", kibibytes: 256)
        try await aged.age(fresh, days: 3)

        let report = await report(fixture)

        #expect(report.projects.map(\.worktree.url.lastPathComponent) == ["fresh", "old"], "biggest first")
        let recent = try #require(report.projects.first)
        #expect(recent.idleDays == 3)
        #expect(recent.status(threshold: 30) == .recent(days: 3))
        #expect(recent.status(threshold: 30).sentence == "You worked here 3 days ago; it will need a reinstall.")
        #expect(report.ready(idleAtLeast: 30).map(\.worktree.url.lastPathComponent) == ["old"])
        #expect(report.all.count == 2)
    }

    @Test func anUnknownIdleClockIsNeverReady() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let aged = AgedRepos(fixture: fixture)
        let busy = try await aged.repo("busy", days: 60, gitignore: Self.gitignore, files: ["a.txt": "a\n", "b.txt": "b\n"])
        try aged.blob(in: busy, "node_modules/a.bin", kibibytes: 8)
        try await aged.age(busy, days: 60)

        let report = await report(fixture) { scanner in
            // The file walk stops at its cap before finishing: idle unknown (PLAN §4.3).
            scanner.idleClock = IdleClock(git: fixture.git, claudeConfigDirectory: fixture.environment().claudeConfigDirectory, maxEntries: 1)
        }

        let project = try #require(report.projects.first)
        #expect(project.idleDays == nil)
        #expect(project.status(threshold: 30) == .idleUnknown)
        #expect(project.status(threshold: 0) == .idleUnknown)
        #expect(report.ready(idleAtLeast: 0).isEmpty)
        #expect(report.idleTotal(atLeast: 0).count == 0)
    }

    @Test func claudeAndCursorWorktreesAreNotRowsAndAreCounted() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let aged = AgedRepos(fixture: fixture)
        let repo = try await aged.repo("app", days: 45, gitignore: Self.gitignore)
        let claude = try await fixture.addClaudeWorktree(to: repo, name: "busy-owl")
        let cursor = try await fixture.addCursorWorktree(to: repo, name: "abc")
        let sibling = try await fixture.addSiblingWorktree(to: repo, name: "task")
        try aged.blob(in: claude, "node_modules/a.bin", kibibytes: 64)
        try aged.blob(in: cursor, "node_modules/a.bin", kibibytes: 32)
        try aged.blob(in: sibling, "node_modules/a.bin", kibibytes: 16)

        let report = await report(fixture)

        #expect(report.projects.map(\.worktree.kind) == [.sibling], "\(report.projects.map(\.worktree.path))")
        #expect(report.leftOut.count == 2)
        #expect(report.leftOut.bytes >= 96 * 1024)
        #expect(report.problems.isEmpty, "\(report.problems)")
    }

    @Test func aTrackedBuildFolderAndASymlinkedNodeModulesAreNotCandidates() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let aged = AgedRepos(fixture: fixture)
        let repo = try await aged.repo("tool", days: 40, gitignore: Self.gitignore)
        try fixture.write("keep me\n", to: "build/release-notes.txt", in: repo)
        try await fixture.run(["add", "-f", "build/release-notes.txt"], in: repo)
        try await fixture.commitAll(in: repo, message: "Track build notes")
        let shared = fixture.url.appending(path: "shared-modules", directoryHint: .isDirectory)
        try aged.blob(in: shared, "left-pad/index.bin", kibibytes: 8)
        try FileManager.default.createSymbolicLink(at: repo.appending(path: "node_modules"), withDestinationURL: shared)
        try aged.blob(in: repo, ".next/cache/a.bin", kibibytes: 8)

        let report = await report(fixture)

        let project = try #require(report.projects.first)
        #expect(project.folders.map(\.relativePath) == [".next"])
        let reasons = Dictionary(uniqueKeysWithValues: project.skipped.map { ($0.relativePath, $0.reason) })
        #expect(reasons["build"] == .hasTrackedFiles)
        #expect(reasons["node_modules"] == .symlink)
        // A checkout with nothing but such folders is no row at all.
        try FileManager.default.removeItem(at: repo.appending(path: ".next"))
        #expect(await self.report(fixture).projects.isEmpty)
    }

    @Test func aProcessInsideBlocksTheProject() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let aged = AgedRepos(fixture: fixture)
        let repo = try await aged.repo("server", days: 40, gitignore: Self.gitignore)
        try aged.blob(in: repo, "node_modules/a.bin", kibibytes: 8)
        try await aged.age(repo, days: 40)
        let inside = ProcessCwdIndex.Entry(pid: 4242, command: "node", cwd: CanonicalPath.resolve(repo.appending(path: "src")))

        let report = await report(fixture, cwdIndex: ProcessCwdIndex(entries: [inside]))
        let project = try #require(report.projects.first)
        #expect(project.blocker == .inUse([inside]))
        #expect(project.status(threshold: 30).label == "In use (node)")
        #expect(report.ready(idleAtLeast: 30).isEmpty)

        let unknown = await self.report(fixture, cwdIndex: .unavailable("lsof not found"))
        #expect(unknown.projects.first?.status(threshold: 30) == .blocked(.inUseUnknown("lsof not found")))
    }

    @Test func aMainCheckoutIsAsRecentAsTheWorktreesInsideIt() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let aged = AgedRepos(fixture: fixture)
        let repo = try await aged.repo("web", days: 60, gitignore: Self.gitignore)
        try aged.blob(in: repo, "node_modules/a.bin", kibibytes: 8)
        let claude = repo.appending(path: ".claude/worktrees/new-idea", directoryHint: .isDirectory)
        try await aged.git(["worktree", "add", "--quiet", "-b", "claude/new-idea", claude.path], in: repo, days: 2)
        try await aged.commitAndPush(claude, file: "idea.md", branch: "claude/new-idea", days: 2)
        try await aged.age(claude, days: 2)
        // The main checkout's own files, its index and HEAD, last: everything but the nested worktree.
        let gitDir = repo.appending(path: ".git")
        for item in [".gitignore", "node_modules/a.bin", "node_modules"] {
            try fixture.setModificationDate(aged.date(daysAgo: 60), of: repo.appending(path: item))
        }
        for name in ["index", "HEAD"] { try fixture.setModificationDate(aged.date(daysAgo: 60), of: gitDir.appending(path: name)) }

        let report = await report(fixture)

        let main = try #require(report.projects.first { $0.worktree.isMain })
        let own = await IdleClock(git: fixture.git, claudeConfigDirectory: fixture.environment().claudeConfigDirectory)
            .report(for: main.worktree)
        #expect(own.idleDays == 60, "on its own it reads 60 days")
        #expect(main.idleDays == 2, "a Claude session worked inside it 2 days ago")
        #expect(main.status(threshold: 30) == .recent(days: 2))
        #expect(report.leftOut.count == 0, "the Claude worktree has no folders of its own")

        // Unknown inside = unknown.
        #expect(ProjectFoldersScanner.combined(.idle(days: 60), nested: [.unknown]).idleDays == nil)
        #expect(ProjectFoldersScanner.combined(.idle(days: 60), nested: [.idle(days: 9), .idle(days: 40)]).idleDays == 9)
        #expect(ProjectFoldersScanner.combined(.idle(days: 5), nested: []).idleDays == 5)
    }

    @Test func aStaleRecordIsNotAProject() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let alpha = try await fixture.makeRepo("alpha")
        let bravo = try await fixture.makeRepo("bravo")
        try fixture.write("node_modules/\n", to: ".gitignore", in: bravo)
        try await fixture.commitAll(in: bravo, message: "Ignore node_modules")
        let shared = fixture.scanRoot.appending(path: "shared", directoryHint: .isDirectory)
        try await fixture.addWorktree(to: alpha, at: shared, branch: "a-task")
        try FileManager.default.removeItem(at: shared)
        try await fixture.addWorktree(to: bravo, at: shared, branch: "b-task")
        try fixture.write("x\n", to: "node_modules/pkg/index.js", in: shared)

        let report = await report(fixture)

        let rows = report.projects.filter { $0.worktree.url.lastPathComponent == "shared" }
        #expect(rows.map(\.worktree.repoPath) == [bravo.path], "only bravo's record is about that folder")
        #expect(report.problems.contains { $0.contains("shared") }, "\(report.problems)")
    }
}
