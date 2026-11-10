import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("WorktreeKind")
struct WorktreeKindTests {
    private func classify(_ path: String, main: String, cursor: String = "/Users/nobody/.cursor/worktrees") -> WorktreeKind {
        WorktreeKind.classify(
            path: URL(fileURLWithPath: path),
            isMain: path == main,
            mainPath: URL(fileURLWithPath: main),
            cursorWorktreesDirectory: URL(fileURLWithPath: cursor)
        )
    }

    @Test func rulesOnPlainPaths() {
        let main = "/Users/me/GitHub/app"
        #expect(classify(main, main: main) == .main)
        #expect(classify("/Users/me/GitHub/app/.claude/worktrees/task-1", main: main) == .claude)
        #expect(classify("/Users/nobody/.cursor/worktrees/app/abc", main: main) == .cursor)
        #expect(classify("/Users/me/GitHub/app-feature", main: main) == .sibling)
        #expect(classify("/Users/me/elsewhere/app-old", main: main) == .other)
    }

    @Test func comparesThroughPrivateTmp() {
        // /tmp is a symlink to /private/tmp: the same folder written two ways.
        #expect(classify("/private/tmp/cc-kinds/app-feature", main: "/tmp/cc-kinds/app") == .sibling)
        #expect(classify("/tmp/cc-kinds/app-feature", main: "/private/tmp/cc-kinds/app") == .sibling)
        #expect(classify(
            "/private/tmp/cc-home/.cursor/worktrees/app/abc",
            main: "/Users/me/GitHub/app",
            cursor: "/tmp/cc-home/.cursor/worktrees"
        ) == .cursor)
        #expect(classify("/tmp/cc-kinds-elsewhere/wt", main: "/private/var/folders/cc/app") == .other)
        #expect(classify("/tmp/wt", main: "/private/var/folders/cc/app") == .other)
    }

    @Test func cursorDirectoryItselfIsNotACursorWorktree() {
        let cursor = "/Users/nobody/.cursor/worktrees"
        #expect(classify(cursor, main: "/Users/nobody/app", cursor: cursor) != .cursor)
    }

    @Test func kindsOnARealFixture() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let repo = try await fixture.makeRepo("app")
        let sibling = try await fixture.addSiblingWorktree(to: repo, name: "feature")
        let claude = try await fixture.addClaudeWorktree(to: repo, name: "task")
        let cursor = try await fixture.addCursorWorktree(to: repo, name: "c1")
        let other = try await fixture.addWorktree(to: repo, at: fixture.url.appending(path: "elsewhere/app-old"))

        let environment = fixture.environment()
        let scanner = WorktreeScanner(
            git: try #require(WorktreeAssessor.git(for: environment)),
            cursorWorktreesDirectory: environment.cursorWorktreesDirectory
        )
        let worktrees = try await scanner.worktrees(in: repo)
        func kind(of url: URL) -> WorktreeKind? {
            worktrees.first { CanonicalPath.same($0.url, url) }?.kind
        }
        #expect(worktrees.count == 5)
        #expect(kind(of: repo) == .main)
        #expect(kind(of: sibling) == .sibling)
        #expect(kind(of: claude) == .claude)
        #expect(kind(of: cursor) == .cursor)
        #expect(kind(of: other) == .other)
        #expect(worktrees.first?.isMain == true)
        #expect(worktrees.allSatisfy { $0.repoPath == repo.path })
    }

    @Test func realGitLockWithoutReasonAndDetach() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let repo = try await fixture.makeRepo("app")
        let feature = try await fixture.addSiblingWorktree(to: repo, name: "feature")
        try await fixture.lock(feature, in: repo)
        try await fixture.detach(feature)

        let environment = fixture.environment()
        let scanner = WorktreeScanner(
            git: try #require(WorktreeAssessor.git(for: environment)),
            cursorWorktreesDirectory: environment.cursorWorktreesDirectory
        )
        let listed = try #require(try await scanner.worktrees(in: repo).last)
        #expect(listed.lockedReason == "")
        #expect(listed.isLocked)
        #expect(listed.isDetached)
        #expect(listed.branch == nil)
        #expect(listed.head?.count == 40)
        #expect(listed.kind == .sibling)
    }
}
