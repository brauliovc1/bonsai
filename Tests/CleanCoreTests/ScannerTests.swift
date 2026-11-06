@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Scanner")
struct ScannerTests {
    /// Collects progress events from the scanner's @Sendable callback.
    final class ProgressLog: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [ScanProgress] = []
        func append(_ event: ScanProgress) { lock.withLock { storage.append(event) } }
        var events: [ScanProgress] { lock.withLock { storage } }
    }

    @Test func endToEndTwoReposFiveWorktrees() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let alpha = try await fixture.makeRepo("alpha")
        let beta = try await fixture.makeRepo("beta", in: fixture.scanRoot.appending(path: "group"))

        try await fixture.addSiblingWorktree(to: alpha, name: "feature")
        try await fixture.addClaudeWorktree(to: alpha, name: "task")
        try await fixture.addCursorWorktree(to: alpha, name: "c1")
        let locked = try await fixture.addSiblingWorktree(to: beta, name: "locked")
        try await fixture.lock(locked, in: beta, reason: "in use")
        let gone = try await fixture.addWorktree(to: beta, at: fixture.url.appending(path: "elsewhere/beta-old"))
        try fixture.deleteFolder(gone)

        let log = ProgressLog()
        let result = await Scanner(environment: fixture.environment())
            .scan(roots: [fixture.scanRoot]) { log.append($0) }

        #expect(result.issues.isEmpty, "\(result.issues)")
        #expect(result.repos == [alpha.path, beta.path])
        #expect(result.worktrees.count == 7)
        #expect(result.worktrees.filter(\.isMain).map(\.repoPath) == [alpha.path, beta.path])

        let kinds = Dictionary(grouping: result.worktrees, by: \.kind).mapValues(\.count)
        #expect(kinds == [.main: 2, .sibling: 2, .claude: 1, .cursor: 1, .other: 1])

        let alphaBranches = result.worktrees(inRepo: alpha.path).map { "\($0.kind.rawValue):\($0.branch ?? "-")" }
        #expect(Set(alphaBranches) == ["main:main", "sibling:feature", "claude:claude/task", "cursor:-"])
        #expect(result.worktrees.first { $0.kind == .cursor }?.isDetached == true)

        let lockedWorktree = try #require(result.worktrees.first { $0.branch == "locked" })
        #expect(lockedWorktree.lockedReason == "in use")
        let prunable = try #require(result.worktrees.first { $0.kind == .other })
        #expect(prunable.isPrunable)
        #expect(prunable.branch == "beta-old")

        for worktree in result.worktrees {
            if worktree.isPrunable {
                #expect(result.size(of: worktree) == nil)
            } else {
                #expect((result.size(of: worktree) ?? 0) > 0, "size of \(worktree.path)")
            }
        }

        let events = log.events
        #expect(events.first == .discoveringRepos(roots: 1))
        #expect(events.contains(.listingWorktrees(completed: 2, total: 2)))
        #expect(events.contains(.measuringSizes(completed: 7, total: 7)))
        #expect(events.last == .finished)

        let encoded = try CleanJSON.encoder().encode(result)
        let decoded = try CleanJSON.decoder().decode(ScanResult.self, from: encoded)
        #expect(decoded.worktrees == result.worktrees)
        #expect(decoded.sizes == result.sizes)
    }

    @Test func brokenRepoBecomesAnIssue() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let alpha = try await fixture.makeRepo("alpha")
        try await fixture.addSiblingWorktree(to: alpha, name: "feature")
        let broken = try await fixture.makeRepo("broken")
        try fixture.corruptHead(of: broken)

        let result = await Scanner(environment: fixture.environment())
            .scan(roots: [fixture.scanRoot], includeSizes: false)

        #expect(result.repos == [alpha.path, broken.path])
        #expect(result.worktrees.map(\.repoPath) == [alpha.path, alpha.path])
        #expect(result.issues.map(\.kind) == [.worktreeListFailed])
        #expect(result.issues.first?.path == broken.path)
        #expect(result.sizes.isEmpty)
    }

    @Test func missingGitIsAnIssue() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        try await fixture.makeRepo("alpha")
        var environment = fixture.environment()
        environment.tools.git = nil

        let result = await Scanner(environment: environment).scan(roots: [fixture.scanRoot], includeSizes: false)
        #expect(result.repos.count == 1)
        #expect(result.worktrees.isEmpty)
        #expect(result.issues.map(\.kind) == [.gitMissing])
    }

    @Test func rootResolutionOrder() throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        var environment = fixture.environment()
        let explicit = [URL(fileURLWithPath: "/explicit")]
        let override = [URL(fileURLWithPath: "/override")]

        #expect(Scanner.resolveRoots(explicit: [], environment: environment).isEmpty)
        let github = fixture.home.appending(path: "Documents/GitHub")
        try FileManager.default.createDirectory(at: github, withIntermediateDirectories: true)
        #expect(Scanner.resolveRoots(explicit: [], environment: environment).map(\.path) == [github.path])
        environment.scanRootsOverride = override
        #expect(Scanner.resolveRoots(explicit: [], environment: environment) == override)
        #expect(Scanner.resolveRoots(explicit: explicit, environment: environment) == explicit)
    }

    @Test func noRootsIsAnIssue() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let result = await Scanner(environment: fixture.environment()).scan()
        #expect(result.roots.isEmpty)
        #expect(result.issues.map(\.kind) == [.noRoots])
    }

    @Test func mainSizeLeavesOutNestedWorktrees() {
        func worktree(_ path: String, main: Bool) -> Worktree {
            Worktree(path: path, repoPath: "/r/app", head: "1", branch: "b", isMain: main, kind: main ? .main : .claude)
        }
        let worktrees = [
            worktree("/r/app", main: true),
            worktree("/r/app/.claude/worktrees/a", main: false),
            worktree("/r/app/.claude/worktrees/b", main: false),
            worktree("/r/app-sibling", main: false),
        ]
        let sizes: [String: Int64] = [
            "/r/app": 10_000, "/r/app/.claude/worktrees/a": 3_000,
            "/r/app/.claude/worktrees/b": 4_000, "/r/app-sibling": 5_000,
        ]
        let adjusted = Scanner.excludingNestedWorktrees(sizes, worktrees: worktrees)
        #expect(adjusted["/r/app"] == 3_000)
        #expect(adjusted["/r/app/.claude/worktrees/a"] == 3_000)
        #expect(adjusted["/r/app-sibling"] == 5_000)

        let clamped = Scanner.excludingNestedWorktrees(["/r/app": 1_000, "/r/app/.claude/worktrees/a": 3_000], worktrees: worktrees)
        #expect(clamped["/r/app"] == 0)
    }
}
