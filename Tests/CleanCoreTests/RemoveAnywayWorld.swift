@testable import CleanCore
import CleanTestSupport
import Foundation

/// A `SafetyWorld` for Remove anyway (PLAN §4.8): a spy git under the remover, so tests see each
/// `worktree remove` exactly as git got it, and helpers for the confirmation's fresh look.
struct RemoveAnywayWorld {
    let safety: SafetyWorld
    let spy: SpyGit

    static func make() async throws -> RemoveAnywayWorld {
        let safety = try await SafetyWorld.make()
        return RemoveAnywayWorld(safety: safety, spy: try SpyGit(fixture: safety.fixture))
    }

    var fixture: GitFixture { safety.fixture }
    var repo: URL { safety.repo }
    var log: RemovalLog { RemovalLog(environment: fixture.environment()) }

    func remove() {
        safety.remove()
    }

    /// Every worktree of the repo, as a scan would know them.
    func known() async throws -> [Worktree] {
        try await WorktreeScanner(git: fixture.git, cursorWorktreesDirectory: fixture.environment().cursorWorktreesDirectory)
            .worktrees(in: repo)
    }

    /// What the confirmation sheet is built from: a fresh assessment (no process inside unless `cwdIndex` says).
    func assess(_ path: URL, cwdIndex: ProcessCwdIndex = ProcessCwdIndex(entries: [])) async throws -> WorktreeAssessment {
        let worktree = try await fixture.worktree(at: path, in: repo)
        let assessor = WorktreeAssessor(git: fixture.git, settings: Settings(), environment: fixture.environment())
        return await assessor.assess(worktree, knownWorktrees: try await known(), cwdIndex: cwdIndex)
    }

    /// A remover whose git is the spy; no process inside unless `cwdIndex` says (nil = the real lsof).
    func remover(cwdIndex: ProcessCwdIndex? = ProcessCwdIndex(entries: [])) -> Remover {
        var remover = Remover(git: spy.git, settings: Settings(), environment: fixture.environment())
        if let cwdIndex { remover.captureCwdIndex = { cwdIndex } }
        return remover
    }

    /// The `worktree remove` calls git got.
    var removeCalls: [[String]] { spy.calls("worktree", "remove") }

    /// The list `assessment` would confirm, built from a fresh inspection even when Remove anyway isn't offered:
    /// what a caller that skipped the checks would pass.
    func listAsIfOffered(_ path: URL) async throws -> LossList {
        let worktree = try await fixture.worktree(at: path, in: repo)
        let state = await SafetyCheck(git: fixture.git).state(of: worktree, knownWorktrees: try await known())
        return RemoveAnyway.lossList(for: worktree, state: state)
    }

    func branchExists(_ branch: String) async -> Bool {
        let result = try? await fixture.git.result(["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"], in: repo)
        return result?.succeeded == true
    }

    /// The worktree's own git dir (`<repo>/.git/worktrees/<name>`).
    func gitDir(of path: URL) async throws -> URL {
        URL(fileURLWithPath: try await fixture.run(["rev-parse", "--absolute-git-dir"], in: path), isDirectory: true)
    }
}

extension LossList {
    /// Each category with its entries as "text" or "text (detail)", for exact comparisons.
    var plain: [LossList.Category: [String]] {
        Dictionary(uniqueKeysWithValues: sections.map { section in
            (section.category, section.entries.map { $0.text + ($0.detail.map { " (\($0))" } ?? "") })
        })
    }
}
