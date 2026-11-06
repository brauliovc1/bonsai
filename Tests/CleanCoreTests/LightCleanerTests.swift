@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// PLAN §4.2 light clean: deleting, with every condition checked again right before each folder goes.
@Suite("LightCleaner")
struct LightCleanerTests {
    /// A sibling worktree with three ignored dependency folders, and its findings.
    private func threeFolders(_ world: LightCleanWorld) async throws -> (URL, Worktree, LightCleanFindings) {
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "three")
        try world.file("node_modules/a.js", in: wt, kibibytes: 8)
        try world.file("packages/a/node_modules/b.js", in: wt)
        try world.file("packages/b/node_modules/c.js", in: wt)
        let worktree = try await world.worktree(wt)
        let findings = await world.finder().candidates(in: worktree)
        try #require(findings.candidates.count == 3)
        return (wt, worktree, findings)
    }

    @Test func deletesTheCandidatesMeasuresAndLogsOnce() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let (wt, worktree, findings) = try await threeFolders(world)

        let result = try await world.cleaner(freeSpace: [1_000, 21_000])
            .clean(worktree, candidates: findings.candidates)

        #expect(result.deleted.map(\.relativePath) == ["node_modules", "packages/a/node_modules", "packages/b/node_modules"])
        #expect(result.refused.isEmpty && result.failed.isEmpty && result.warnings.isEmpty && result.logged)
        #expect(!world.exists("node_modules", in: wt))
        #expect(world.exists("packages/a", in: wt) && world.exists("README.md", in: wt))
        #expect(result.freedBytes == 20_000)

        let entries = try world.log.entries()
        let entry = try #require(entries.first)
        #expect(entries.count == 1 && entry == result.entry)
        #expect(entry.action == .lightClean && entry.mode == .manual && !entry.isRestorable)
        #expect(entry.repoPath == worktree.repoPath && entry.path == worktree.path)
        #expect(entry.branch == "three" && entry.headSha == worktree.head && entry.kind == .sibling)
        #expect(entry.estimatedBytes == Int64(16 * 1024))
        #expect(entry.freedBytes == 20_000)
        #expect(entry.notes == ["deleted node_modules", "deleted packages/a/node_modules", "deleted packages/b/node_modules"])
    }

    @Test func aCandidateTrackedSinceTheFindIsRefusedAndTheOthersAreCleaned() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let (wt, worktree, findings) = try await threeFolders(world)
        try await world.fixture.run(["add", "-f", "packages/a/node_modules/b.js"], in: wt)

        let result = try await world.cleaner().clean(worktree, candidates: findings.candidates)

        #expect(result.deleted.map(\.relativePath) == ["node_modules", "packages/b/node_modules"])
        #expect(result.refused == [LightCleanSkip(relativePath: "packages/a/node_modules", name: "node_modules", reason: .hasTrackedFiles)])
        #expect(world.exists("packages/a/node_modules/b.js", in: wt))
        let entry = try #require(try world.log.entries().first)
        #expect(entry.notes == [
            "deleted node_modules",
            "deleted packages/b/node_modules",
            "refused packages/a/node_modules: git tracks files inside it.",
        ])
    }

    @Test func aCheckoutThatAppearsInsideSinceTheFindIsRefused() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let (wt, worktree, findings) = try await threeFolders(world)
        let clone = try await world.packageClone(in: wt, at: "packages/b/node_modules/dep")
        try world.fixture.write("mine\n", to: "Mine.swift", in: clone)

        let result = try await world.cleaner().clean(worktree, candidates: findings.candidates)

        #expect(result.deleted.map(\.relativePath) == ["node_modules", "packages/a/node_modules"])
        #expect(result.refused.map(\.reason) == [.nestedCheckout(["dep"])])
        #expect(world.exists("packages/b/node_modules/dep/Mine.swift", in: wt))
    }

    @Test func aParentReplacedByASymlinkIsRefused() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let (wt, worktree, findings) = try await threeFolders(world)
        // packages/a now points at a folder outside the worktree that has its own node_modules.
        let outside = world.fixture.url.appending(path: "outside")
        try world.file("node_modules/keep.js", in: outside)
        try FileManager.default.removeItem(at: wt.appending(path: "packages/a"))
        try FileManager.default.createSymbolicLink(at: wt.appending(path: "packages/a"), withDestinationURL: outside)

        let result = try await world.cleaner().clean(worktree, candidates: findings.candidates)

        #expect(result.refused.map(\.reason) == [.notACandidate("packages/a is not a plain folder")])
        #expect(world.exists("node_modules/keep.js", in: outside))
    }

    @Test func aCandidateReplacedByASymlinkSinceTheFindIsRefused() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let (wt, worktree, findings) = try await threeFolders(world)
        // The link points at another ignored folder of the same worktree, so every git check would pass.
        let link = wt.appending(path: "node_modules")
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "packages/b/node_modules")

        let result = try await world.cleaner().clean(worktree, candidates: findings.candidates)

        #expect(result.refused == [LightCleanSkip(relativePath: "node_modules", name: "node_modules", reason: .symlink)])
        #expect(result.deleted.map(\.relativePath) == ["packages/a/node_modules", "packages/b/node_modules"])
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == "packages/b/node_modules")
    }

    @Test func symlinksInsideAreDeletedNotFollowed() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "links")
        let outside = world.fixture.url.appending(path: "shared-store")
        try world.file("pkg/index.js", in: outside)
        try world.file("node_modules/real.js", in: wt)
        try FileManager.default.createSymbolicLink(at: wt.appending(path: "node_modules/pkg"), withDestinationURL: outside.appending(path: "pkg"))
        let worktree = try await world.worktree(wt)
        let findings = await world.finder().candidates(in: worktree)

        let result = try await world.cleaner().clean(worktree, candidates: findings.candidates)

        #expect(result.deleted.count == 1)
        #expect(!world.exists("node_modules", in: wt))
        #expect(world.exists("pkg/index.js", in: outside))
    }

    @Test func anInUseWorktreeIsRefusedAndNothingIsDeleted() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let (wt, worktree, findings) = try await threeFolders(world)
        let shell = SleepingProcess()
        defer { shell.stop() }
        try shell.start(in: wt.appending(path: "packages"))

        await #expect {
            _ = try await world.cleaner(cwdIndex: nil).clean(worktree, candidates: findings.candidates)
        } throws: { error in
            guard case LightCleanError.inUse(let processes) = error else { return false }
            return processes.map(\.command).contains("sleep")
        }
        #expect(world.exists("node_modules/a.js", in: wt))
        #expect(try world.log.entries().isEmpty)
    }

    @Test func aProcessThatEntersAfterTheRecheckIsCaught() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let (wt, worktree, findings) = try await threeFolders(world)
        let shell = SleepingProcess()
        defer { shell.stop() }
        var cleaner = world.cleaner(cwdIndex: nil)
        cleaner.afterRecheck = { _ in try? shell.start(in: wt) }

        await #expect(throws: LightCleanError.self) {
            _ = try await cleaner.clean(worktree, candidates: findings.candidates)
        }
        #expect(world.exists("node_modules/a.js", in: wt))
    }

    @Test func aProcessFoundAfterTheFirstDeleteStopsTheRestAndTheDeleteIsLogged() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let (wt, worktree, findings) = try await threeFolders(world)
        let inside = ProcessCwdIndex.Entry(pid: 42, command: "zsh", cwd: CanonicalPath.resolve(wt))
        let calls = Counter()
        var cleaner = world.cleaner()
        cleaner.captureCwdIndex = { calls.next() == 1 ? ProcessCwdIndex(entries: []) : ProcessCwdIndex(entries: [inside]) }

        let result = try await cleaner.clean(worktree, candidates: findings.candidates)

        #expect(result.deleted.map(\.relativePath) == ["node_modules"])
        #expect(result.refused.map(\.relativePath) == ["packages/a/node_modules", "packages/b/node_modules"])
        #expect(result.refused.allSatisfy { $0.reason == .inUse([inside]) })
        #expect(world.exists("packages/a/node_modules/b.js", in: wt))
        #expect(try world.log.entries().first?.notes.count == 3)
    }

    @Test func noProcessIndexMeansNothingIsDeleted() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let (wt, worktree, findings) = try await threeFolders(world)

        await #expect(throws: LightCleanError.inUseUnknown("lsof not found")) {
            _ = try await world.cleaner(cwdIndex: .unavailable("lsof not found")).clean(worktree, candidates: findings.candidates)
        }
        #expect(world.exists("node_modules/a.js", in: wt))
    }

    @Test func aWorktreeNoLongerRegisteredIsRefused() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let (wt, worktree, findings) = try await threeFolders(world)
        try await world.fixture.run(["worktree", "remove", "--force", wt.path], in: world.repo)
        try world.file("node_modules/a.js", in: wt)

        await #expect(throws: LightCleanError.notRegistered(path: worktree.path)) {
            _ = try await world.cleaner().clean(worktree, candidates: findings.candidates)
        }
        #expect(world.exists("node_modules/a.js", in: wt))
    }

    @Test func candidatesOfAnotherWorktreeAreRefused() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let (wt, _, findings) = try await threeFolders(world)
        let other = try await world.fixture.addSiblingWorktree(to: world.repo, name: "other")
        try world.file("node_modules/a.js", in: other)

        let result = try await world.cleaner().clean(try await world.worktree(other), candidates: findings.candidates)

        #expect(result.deleted.isEmpty && result.entry == nil)
        #expect(result.refused.count == 3)
        #expect(result.refused.allSatisfy { if case .notACandidate = $0.reason { true } else { false } })
        #expect(world.exists("node_modules/a.js", in: wt) && world.exists("node_modules/a.js", in: other))
        #expect(try world.log.entries().isEmpty)
    }

    @Test func nothingDeletedMeansNothingLogged() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let (wt, worktree, findings) = try await threeFolders(world)
        for relative in ["node_modules", "packages/a/node_modules", "packages/b/node_modules"] {
            try FileManager.default.removeItem(at: wt.appending(path: relative))
        }

        let result = try await world.cleaner().clean(worktree, candidates: findings.candidates)
        #expect(result.refused.map(\.reason) == [.gone, .gone, .gone])
        #expect(result.entry == nil && result.freedBytes == nil)
        #expect(try world.log.entries().isEmpty)
    }
}

/// Counts calls from `@Sendable` closures.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}
