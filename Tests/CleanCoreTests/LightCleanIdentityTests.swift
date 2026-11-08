@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// Wave 4: light clean deletes only in the worktree it was shown, and only while the folder is still
/// that repo's worktree.
@Suite("LightCleaner: whose folder it is")
struct LightCleanIdentityTests {
    /// alpha's worktree `shared` with a node_modules, and the findings made while it really was alpha's.
    private struct Swap {
        let world: LightCleanWorld
        let shared: URL
        let alphaRecord: Worktree
        let findings: LightCleanFindings
        let bravo: URL
    }

    private func makeSwap() async throws -> Swap {
        let world = try await LightCleanWorld.make("alpha")
        let bravo = try await world.fixture.makeRepo("bravo")
        try world.fixture.write(LightCleanWorld.gitignore, to: ".gitignore", in: bravo)
        try await world.fixture.commitAll(in: bravo, message: "Ignore dependencies")
        let shared = world.fixture.scanRoot.appending(path: "shared", directoryHint: .isDirectory)
        try await world.fixture.addWorktree(to: world.repo, at: shared, branch: "a-task")
        try world.file("node_modules/pkg/index.js", in: shared)
        let record = try await world.worktree(shared)
        let findings = await world.finder().candidates(in: record)
        try #require(findings.candidates.map(\.relativePath) == ["node_modules"])
        return Swap(world: world, shared: shared, alphaRecord: record, findings: findings, bravo: bravo)
    }

    /// alpha's folder is deleted by hand and bravo puts a worktree of its own at the same path, with a
    /// node_modules that bravo ignores too.
    private func swapInBravo(_ swap: Swap) async throws {
        try FileManager.default.removeItem(at: swap.shared)
        try await swap.world.fixture.addWorktree(to: swap.bravo, at: swap.shared, branch: "b-task")
        try swap.world.file("node_modules/pkg/index.js", in: swap.shared)
    }

    @Test func aStaleRecordIsRefusedAndNothingIsDeleted() async throws {
        let swap = try await makeSwap()
        defer { swap.world.remove() }
        try await swapInBravo(swap)
        // git still lists the folder under alpha, and nothing marks it prunable: the folder exists.
        let listed = try await swap.world.known()
        #expect(listed.contains { CanonicalPath.same($0.url, swap.shared) && !$0.isPrunable })

        var message = ""
        do {
            _ = try await swap.world.cleaner().clean(swap.alphaRecord, candidates: swap.findings.candidates)
            Issue.record("expected a refusal")
        } catch let error as LightCleanError {
            guard case .wrongFolder(let why) = error else {
                Issue.record("expected wrongFolder, got \(error)")
                return
            }
            message = why
        }

        #expect(message.contains("another repo's folder"), "\(message)")
        #expect(swap.world.exists("node_modules/pkg/index.js", in: swap.shared), "bravo's folder is untouched")
        #expect(try swap.world.log.entries().isEmpty, "nothing was logged under repo alpha")
    }

    @Test func theIdentityIsCheckedAgainRightBeforeEachDelete() async throws {
        let swap = try await makeSwap()
        defer { swap.world.remove() }
        try swap.world.file("packages/a/node_modules/x.js", in: swap.shared)
        let findings = await swap.world.finder().candidates(in: swap.alphaRecord)
        try #require(findings.candidates.count == 2)
        var cleaner = swap.world.cleaner()
        // After the first folder is checked and before it is deleted, the folder becomes bravo's.
        let once = Once()
        cleaner.afterRecheck = { _ in
            guard once.first() else { return }
            try? await swapInBravo(swap)
        }

        var thrown: LightCleanError?
        do {
            _ = try await cleaner.clean(swap.alphaRecord, candidates: findings.candidates)
        } catch let error as LightCleanError {
            thrown = error
        }

        guard case .wrongFolder = thrown else {
            Issue.record("expected wrongFolder, got \(String(describing: thrown))")
            return
        }
        #expect(swap.world.exists("node_modules/pkg/index.js", in: swap.shared))
        #expect(try swap.world.log.entries().isEmpty)
    }

    @Test func theIdentityBlockerSeparatesThisReposFoldersFromOthers() async throws {
        let swap = try await makeSwap()
        defer { swap.world.remove() }
        let check = SafetyCheck(git: swap.world.fixture.git)
        let main = try await swap.world.worktree(swap.world.repo)
        #expect(main.isMain)
        let mainBlocker = await check.identityBlocker(of: main)
        #expect(mainBlocker == nil, "a main checkout's .git directory is this repo's: \(String(describing: mainBlocker))")
        let linkedBlocker = await check.identityBlocker(of: swap.alphaRecord)
        #expect(linkedBlocker == nil)

        // The folder's .git file is gone: git would describe an enclosing repo, or none.
        try FileManager.default.removeItem(at: swap.shared.appending(path: ".git"))
        let broken = await check.identityBlocker(of: swap.alphaRecord)
        guard case .gitError? = broken else {
            Issue.record("expected a git error, got \(String(describing: broken))")
            return
        }

        try await swapInBravo(swap)
        let stale = await check.identityBlocker(of: swap.alphaRecord)
        guard case .staleRecord(let leadsTo)? = stale else {
            Issue.record("expected a stale record, got \(String(describing: stale))")
            return
        }
        #expect(leadsTo.contains("bravo"))
        let bravoRecord = try await swap.world.worktree(swap.shared, in: swap.bravo)
        let bravoBlocker = await check.identityBlocker(of: bravoRecord)
        #expect(bravoBlocker == nil, "the same folder is fine under the repo it belongs to")
    }

    // MARK: - What was confirmed

    private func sibling(_ world: LightCleanWorld) async throws -> (URL, Worktree, LightCleanFindings) {
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "one")
        try world.file("node_modules/a.js", in: wt)
        let worktree = try await world.worktree(wt)
        let findings = await world.finder().candidates(in: worktree)
        try #require(findings.candidates.count == 1)
        return (wt, worktree, findings)
    }

    @Test func theConfirmedWorktreeIsCleaned() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let (wt, worktree, findings) = try await sibling(world)

        let result = try await world.cleaner().clean(
            worktree, candidates: findings.candidates, expectation: LightCleanExpectation(worktree: worktree)
        )

        #expect(result.deleted.map(\.relativePath) == ["node_modules"])
        #expect(!world.exists("node_modules", in: wt))
    }

    @Test func aWorktreeWhoseHeadBranchOrRepoChangedSinceConfirmationIsRefused() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let (wt, worktree, findings) = try await sibling(world)
        let confirmed = LightCleanExpectation(worktree: worktree)

        // HEAD moved: a commit was made in the worktree.
        try world.fixture.write("more\n", to: "notes.md", in: wt)
        try await world.fixture.commitAll(in: wt, message: "More")
        try await expectRefusal(world, worktree, findings, confirmed, containing: "HEAD moved")

        // The branch changed.
        let moved = try await world.worktree(wt)
        let afterCommit = LightCleanExpectation(worktree: moved)
        try await world.fixture.run(["switch", "--quiet", "-c", "other"], in: wt)
        try await expectRefusal(world, moved, findings, afterCommit, containing: "The branch is now other (was one)")

        // Another repo lists it.
        var wrongRepo = LightCleanExpectation(worktree: try await world.worktree(wt))
        wrongRepo.repoPath = world.fixture.scanRoot.appending(path: "somewhere-else").path
        try await expectRefusal(world, try await world.worktree(wt), findings, wrongRepo, containing: "It is now listed by")

        #expect(world.exists("node_modules/a.js", in: wt), "nothing was deleted")
        #expect(try world.log.entries().isEmpty)
    }

    private func expectRefusal(
        _ world: LightCleanWorld, _ worktree: Worktree, _ findings: LightCleanFindings,
        _ expectation: LightCleanExpectation, containing text: String
    ) async throws {
        do {
            _ = try await world.cleaner().clean(worktree, candidates: findings.candidates, expectation: expectation)
            Issue.record("expected a refusal containing \"\(text)\"")
        } catch let error as LightCleanError {
            guard case .changed(_, let changes) = error else {
                Issue.record("expected changed, got \(error)")
                return
            }
            #expect(changes.joined(separator: " ").contains(text), "\(changes)")
        }
    }
}

/// True for the first caller only.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func first() -> Bool {
        lock.withLock {
            defer { used = true }
            return !used
        }
    }
}
