@testable import CleanCore
import CleanTestSupport
import Foundation

/// A fixture repo set up for the §4.1 checks: `.gitignore` ignores `.env`, `node_modules/`, `*.log`,
/// `/.claude/worktrees/`, `.venv/` and `.build/`, and is pushed to `origin/main`.
struct SafetyWorld {
    let fixture: GitFixture
    let repo: URL

    static let gitignore = ".env\nnode_modules/\n*.log\n/.claude/worktrees/\n.venv/\n.build/\n"

    static func make(_ name: String = "alpha") async throws -> SafetyWorld {
        let fixture = try GitFixture()
        let repo = try await fixture.makeRepo(name)
        try fixture.write(gitignore, to: ".gitignore", in: repo)
        try await fixture.commitAll(in: repo, message: "Ignore files")
        try await fixture.run(["push", "--quiet", "origin", "main"], in: repo)
        return SafetyWorld(fixture: fixture, repo: repo)
    }

    func remove() {
        fixture.remove()
    }

    /// A clean sibling worktree on a new branch from `main`.
    func sibling(_ name: String) async throws -> URL {
        try await fixture.addSiblingWorktree(to: repo, name: name)
    }

    func worktree(_ path: URL, in repo: URL? = nil) async throws -> Worktree {
        try await fixture.worktree(at: path, in: repo ?? self.repo)
    }

    /// The §4.1 verdict. Defaults: idle 40 days, default settings, no process inside.
    func check(
        _ path: URL,
        in repo: URL? = nil,
        idle: IdleReport = .idle(days: 40),
        settings: Settings = Settings(),
        cwdIndex: ProcessCwdIndex = ProcessCwdIndex(entries: []),
        knownWorktrees: [Worktree]? = nil,
        nestedSearch: NestedCheckoutSearch = NestedCheckoutSearch()
    ) async throws -> SafetyReport {
        let repo = repo ?? self.repo
        let worktree = try await worktree(path, in: repo)
        var known = knownWorktrees ?? []
        if knownWorktrees == nil {
            known = try await WorktreeScanner(
                git: fixture.git,
                cursorWorktreesDirectory: fixture.environment().cursorWorktreesDirectory
            ).worktrees(in: repo)
        }
        var safetyCheck = SafetyCheck(git: fixture.git)
        safetyCheck.inspector.nestedSearch = nestedSearch
        return await safetyCheck.check(worktree, idle: idle, settings: settings, cwdIndex: cwdIndex, knownWorktrees: known)
    }
}
