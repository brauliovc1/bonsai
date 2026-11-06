@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Restorer and Pruner")
struct RestorerTests {
    private func removeLogged(_ path: URL, _ world: SafetyWorld) async throws -> RemovalLogEntry {
        let remover = Remover(git: world.fixture.git, settings: Settings(), environment: world.fixture.environment())
        return try await remover.remove(try await world.worktree(path), mode: .manual, estimatedBytes: nil).entry
    }

    private func restorer(_ world: SafetyWorld) -> Restorer {
        Restorer(git: world.fixture.git, environment: world.fixture.environment())
    }

    @Test func branchRoundTrip() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("feature")
        try world.fixture.write("work\n", to: "work.txt", in: wt)
        try await world.fixture.commitAll(in: wt)
        let entry = try await removeLogged(wt, world)
        #expect(!FileManager.default.fileExists(atPath: wt.path))

        let plan = try await restorer(world).plan(entryID: entry.id)
        #expect(plan.arguments == ["worktree", "add", entry.path, "feature"])

        let result = try await restorer(world).restore(entryID: entry.id)
        #expect(result.ref == "feature" && result.warnings.isEmpty)
        #expect(result.note == Restorer.dependenciesNote)
        #expect(try await world.fixture.run(["rev-parse", "--abbrev-ref", "HEAD"], in: wt) == "feature")
        #expect(FileManager.default.fileExists(atPath: wt.appending(path: "work.txt").path))

        let saved = try #require(try RemovalLog(environment: world.fixture.environment()).entry(id: entry.id))
        #expect(saved.restoredAt != nil)
        await #expect {
            try await restorer(world).restore(entryID: entry.id)
        } throws: { error in
            if case Restorer.RestoreError.alreadyRestored = error { return true }
            return false
        }
    }

    @Test func detachedRoundTrip() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addWorktree(to: world.repo, at: world.fixture.url.appending(path: "det"), detached: true)
        let sha = try await world.fixture.run(["rev-parse", "HEAD"], in: wt)
        let entry = try await removeLogged(wt, world)
        #expect(entry.branch == nil && entry.headSha == sha)

        let plan = try await restorer(world).plan(entryID: entry.id)
        #expect(plan.arguments == ["worktree", "add", "--detach", entry.path, sha])
        _ = try await restorer(world).restore(entryID: entry.id)
        #expect(try await world.fixture.run(["rev-parse", "HEAD"], in: wt) == sha)
        let symbolic = try await world.fixture.git.result(["symbolic-ref", "-q", "HEAD"], in: wt)
        #expect(!symbolic.succeeded)
    }

    @Test func refusesWhenThePathExists() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("taken")
        let entry = try await removeLogged(wt, world)
        try world.fixture.write("someone else's\n", to: "file.txt", in: wt)

        await #expect(throws: Restorer.RestoreError.pathExists(entry.path)) {
            try await restorer(world).restore(entryID: entry.id)
        }
        #expect(try String(contentsOf: wt.appending(path: "file.txt"), encoding: .utf8) == "someone else's\n")
        #expect(try RemovalLog(environment: world.fixture.environment()).entry(id: entry.id)?.restoredAt == nil)
    }

    @Test func refusesUnknownIDsAndPruneEntries() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let gone = try await world.sibling("gone")
        try world.fixture.deleteFolder(gone)
        let pruned = try await Pruner(git: world.fixture.git, environment: world.fixture.environment()).prune(repo: world.repo)
        let entry = try #require(pruned.entry)

        await #expect(throws: Restorer.RestoreError.notAWorktreeRemoval(.worktreePrune)) {
            try await restorer(world).restore(entryID: entry.id)
        }
        let unknown = UUID()
        await #expect(throws: Restorer.RestoreError.notFound(unknown.uuidString)) {
            try await restorer(world).restore(entryID: unknown)
        }
    }

    @Test func prunePreviewsThenPrunesAndLogs() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let gone = try await world.sibling("gone")
        let kept = try await world.sibling("kept")
        try world.fixture.deleteFolder(gone)
        let pruner = Pruner(git: world.fixture.git, environment: world.fixture.environment())

        let preview = try await pruner.preview(repo: world.repo)
        #expect(preview.count == 1)
        #expect(preview.first?.hasPrefix("worktrees/") == true)
        #expect(try await world.fixture.worktree(at: gone, in: world.repo).isPrunable)

        let result = try await pruner.prune(repo: world.repo)
        #expect(result.pruned == preview)
        let paths = try await WorktreeScanner(git: world.fixture.git, cursorWorktreesDirectory: world.fixture.url)
            .worktrees(in: world.repo).map(\.path)
        #expect(paths.count == 2)
        #expect(paths.contains { CanonicalPath.same(URL(fileURLWithPath: $0), kept) })

        let entries = try RemovalLog(environment: world.fixture.environment()).entries()
        #expect(entries.map(\.action) == [.worktreePrune])
        #expect(entries.first?.notes == preview)
        #expect(entries.first?.repoPath == world.repo.path)

        let again = try await pruner.prune(repo: world.repo)
        #expect(again.pruned.isEmpty && again.entry == nil)
        #expect(try RemovalLog(environment: world.fixture.environment()).entries().count == 1)
    }
}
