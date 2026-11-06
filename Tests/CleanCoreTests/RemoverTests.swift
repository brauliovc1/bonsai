@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Remover")
struct RemoverTests {
    private func remover(_ world: SafetyWorld, settings: Settings = Settings(), clockOffset: TimeInterval = 0) -> Remover {
        Remover(git: world.fixture.git, settings: settings, environment: world.fixture.environment(clockOffset: clockOffset))
    }

    private func log(_ world: SafetyWorld) -> RemovalLog {
        RemovalLog(environment: world.fixture.environment())
    }

    private func branchExists(_ branch: String, _ world: SafetyWorld) async -> Bool {
        let result = try? await world.fixture.git.result(["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"], in: world.repo)
        return result?.succeeded == true
    }

    @Test func removesKeepsTheBranchAndLogs() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("done")
        try world.fixture.write(String(repeating: "x", count: 200_000), to: "node_modules/big/blob.js", in: wt)
        let worktree = try await world.worktree(wt)

        let result = try await remover(world).remove(worktree, mode: .manual, estimatedBytes: 4096)
        #expect(!FileManager.default.fileExists(atPath: wt.path))
        #expect(await branchExists("done", world))
        #expect(result.logged && result.warnings.isEmpty, "\(result.warnings)")

        let entries = try log(world).entries()
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry == result.entry)
        #expect(entry.action == .worktreeRemove && entry.mode == .manual)
        #expect(entry.branch == "done" && entry.headSha == worktree.head && entry.kind == .sibling)
        #expect(entry.path == worktree.path && entry.repoPath == world.repo.path)
        #expect(entry.estimatedBytes == 4096)
        #expect(entry.freedBytes != nil)
        #expect(entry.restoredAt == nil)
    }

    @Test func stateChangedSinceTheScanIsRefused() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("changed")
        let worktree = try await world.worktree(wt)
        let scanned = try await world.check(wt)
        #expect(scanned.manualAllowed)

        try world.fixture.write("new work\n", to: "draft.md", in: wt)
        await #expect {
            try await remover(world).remove(worktree, mode: .manual, estimatedBytes: nil)
        } throws: { error in
            guard case RemovalError.refused(.manual, let report) = error else { return false }
            return report.blockers == [.uncommitted(count: 1)]
        }
        #expect(FileManager.default.fileExists(atPath: wt.appending(path: "draft.md").path))
        #expect(try log(world).entries().isEmpty)
    }

    @Test func gitRefusingIsAnErrorAndLogsNothing() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("race")
        let worktree = try await world.worktree(wt)
        var remover = remover(world)
        // The change lands after the re-check, right before git runs: git's own check must catch it.
        let fixture = world.fixture
        remover.beforeGitRemove = { _ = try? fixture.write("late\n", to: "late.txt", in: wt) }

        await #expect {
            try await remover.remove(worktree, mode: .manual, estimatedBytes: nil)
        } throws: { error in
            guard case RemovalError.gitFailed(let stderr) = error else { return false }
            return stderr.contains("modified or untracked files")
        }
        #expect(FileManager.default.fileExists(atPath: wt.appending(path: "late.txt").path))
        #expect(!FileManager.default.fileExists(atPath: log(world).fileURL.path))
    }

    @Test func lockedWorktreeIsNeverRemoved() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("keep")
        try await world.fixture.lock(wt, in: world.repo)
        let worktree = try await world.worktree(wt)
        let remover = remover(world, clockOffset: 40 * 86_400)

        for mode in [RemovalMode.manual, .auto] {
            await #expect(throws: RemovalError.self) {
                try await remover.remove(worktree, mode: mode, estimatedBytes: nil)
            }
        }
        #expect(FileManager.default.fileExists(atPath: wt.appending(path: "README.md").path))

        // Locked after the re-check: git refuses on its own.
        let racy = try await world.sibling("racy")
        var lateLock = remover
        let fixture = world.fixture
        let repo = world.repo
        lateLock.beforeGitRemove = { try? await fixture.lock(racy, in: repo) }
        await #expect {
            try await lateLock.remove(try await world.worktree(racy), mode: .manual, estimatedBytes: nil)
        } throws: { error in
            if case RemovalError.gitFailed = error { return true }
            return false
        }
        #expect(FileManager.default.fileExists(atPath: racy.appending(path: "README.md").path))
        #expect(try log(world).entries().isEmpty)
    }

    @Test func autoModeRechecksEveryAutoRule() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let recent = try await world.sibling("recent")
        let env = try await world.sibling("env")
        try world.fixture.write("A=1\n", to: ".env", in: env)

        // Idle 0 days with the real clock: auto refuses, manual would not.
        await #expect(throws: RemovalError.self) {
            try await remover(world).remove(try await world.worktree(recent), mode: .auto, estimatedBytes: nil)
        }
        // Idle 40 days but an ignored user file: auto refuses.
        let later = remover(world, clockOffset: 40 * 86_400)
        await #expect(throws: RemovalError.self) {
            try await later.remove(try await world.worktree(env), mode: .auto, estimatedBytes: nil)
        }
        #expect(FileManager.default.fileExists(atPath: env.appending(path: ".env").path))

        let result = try await later.remove(try await world.worktree(recent), mode: .auto, estimatedBytes: nil)
        #expect(result.entry.mode == .auto)
        #expect(!FileManager.default.fileExists(atPath: recent.path))
    }

    @Test func mainCheckoutAndUnknownPathsAreRefused() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let main = try await world.worktree(world.repo)
        await #expect(throws: RemovalError.self) {
            try await remover(world).remove(main, mode: .manual, estimatedBytes: nil)
        }
        var stranger = main
        stranger.path = world.fixture.url.appending(path: "not-a-worktree").path
        stranger.isMain = false
        await #expect {
            try await remover(world).remove(stranger, mode: .manual, estimatedBytes: nil)
        } throws: { error in
            if case RemovalError.notRegistered = error { return true }
            return false
        }
        #expect(FileManager.default.fileExists(atPath: world.repo.appending(path: "README.md").path))
    }

    // Item 11: the process index is taken last, so a shell opened during the slow walks is still seen.
    @Test func processThatEntersDuringTheChecksIsCaught() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("late-shell")
        let worktree = try await world.worktree(wt)
        let shell = SleepingProcess()
        defer { shell.stop() }
        var remover = remover(world)
        remover.afterInspection = { try? shell.start(in: wt) }

        await #expect {
            try await remover.remove(worktree, mode: .manual, estimatedBytes: nil)
        } throws: { error in
            guard case RemovalError.refused(.manual, let report) = error else { return false }
            return report.status == .inUse
        }
        #expect(FileManager.default.fileExists(atPath: wt.appending(path: "README.md").path))
    }

    // Item 3: a registered worktree of another repo inside, hidden from the disk walk by an unreadable folder.
    @Test func registeredWorktreesOfOtherReposAreChecked() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let beta = try await world.fixture.makeRepo("beta")
        let outer = try await world.sibling("outer")
        let hidden = outer.appending(path: "node_modules/cache")
        try await world.fixture.addWorktree(to: beta, at: hidden.appending(path: "inner"), branch: "inner")
        let scanner = WorktreeScanner(git: world.fixture.git, cursorWorktreesDirectory: world.fixture.url)
        let known = try await scanner.worktrees(in: world.repo) + scanner.worktrees(in: beta)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: hidden.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hidden.path) }
        let worktree = try await world.worktree(outer)

        // Only this repo's worktrees: the walk can't see inside, so it is just a note for manual.
        #expect(try await world.check(outer).manualAllowed)

        await #expect {
            try await remover(world).remove(worktree, mode: .manual, estimatedBytes: nil, knownWorktrees: known)
        } throws: { error in
            guard case RemovalError.refused(.manual, let report) = error else { return false }
            return report.blockers == [.nestedCheckouts(["node_modules/cache/inner"])]
        }
        #expect(FileManager.default.fileExists(atPath: outer.appending(path: "README.md").path))
    }
}
