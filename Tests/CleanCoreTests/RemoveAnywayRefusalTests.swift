@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// PLAN §4.8: where Remove anyway is never offered, and refused even when called directly; and the re-check
/// right before the delete, which refuses on any change since the confirmation. Nothing is deleted, nothing is
/// logged and git never sees `--force` in any of them.
@Suite("Remove anyway: refusals")
struct RemoveAnywayRefusalTests {
    enum Never: String, CaseIterable {
        case mainCheckout, missingFolder, locked, inUse, maybeInUse, operationInProgress, gitError, registeredWorktreeInside
    }

    /// Each worktree also has an untracked file, so only the never-overridable blocker stands in the way.
    @Test(arguments: Never.allCases)
    func neverOfferedAndRefusedWhenCalledDirectly(_ never: Never) async throws {
        let world = try await RemoveAnywayWorld.make()
        defer { world.remove() }
        var target = try await world.safety.sibling("target")
        try world.fixture.write("draft\n", to: "draft.md", in: target)
        var assessIndex = ProcessCwdIndex(entries: [])
        var removeIndex: ProcessCwdIndex? = ProcessCwdIndex(entries: [])
        switch never {
        case .mainCheckout:
            target = world.repo
        case .missingFolder:
            try world.fixture.deleteFolder(target)
        case .locked:
            try await world.fixture.lock(target, in: world.repo, reason: "on a drive")
        case .inUse:
            let inside = ProcessCwdIndex(entries: [.init(pid: 7, command: "node", cwd: CanonicalPath.resolve(target))])
            (assessIndex, removeIndex) = (inside, inside)
        case .maybeInUse:
            (assessIndex, removeIndex) = (.unavailable("lsof not found"), .unavailable("lsof not found"))
        case .operationInProgress:
            let head = try await world.fixture.run(["rev-parse", "HEAD"], in: target)
            try world.fixture.write(head + "\n", to: "MERGE_HEAD", in: try await world.gitDir(of: target))
        case .gitError:
            try world.fixture.write("this is not a ref\n", to: "HEAD", in: try await world.gitDir(of: target))
        case .registeredWorktreeInside:
            try await world.fixture.addWorktree(to: world.repo, at: target.appending(path: "node_modules/inner"), branch: "inner")
        }

        let worktree = try await world.fixture.worktree(at: target, in: world.repo)
        let assessment = try await world.assess(target, cwdIndex: assessIndex)
        guard case .unavailable(let reason) = assessment.removeAnyway else {
            Issue.record("\(never): offered \(assessment.removeAnyway)")
            return
        }
        #expect(!RemoveAnyway.isOverridable(reason, isBlocker: true) || never == .registeredWorktreeInside, "\(never): \(reason)")

        // Called directly, with the list a careless caller would build and the matching expectation, it is refused.
        let list = try await world.listAsIfOffered(target)
        await #expect(throws: (any Error).self, "\(never)") {
            try await world.remover(cwdIndex: removeIndex).removeAnyway(
                worktree, confirmed: list, expectation: RemovalExpectation(assessment: assessment),
                estimatedBytes: nil, knownWorktrees: try await world.known()
            )
        }
        #expect(world.removeCalls.isEmpty, "\(never): \(world.removeCalls)")
        #expect(try world.log.entries().isEmpty)
        if never != .missingFolder {
            #expect(FileManager.default.fileExists(atPath: target.appending(path: never == .mainCheckout ? "README.md" : "draft.md").path))
        }
    }

    /// The verdict refuses a state whose entries don't add up to its counts: the list would not be exact.
    @Test func aStateThatCannotListItsEntriesIsNeverOffered() {
        let branch = Worktree(path: "/tmp/w", repoPath: "/tmp/alpha", head: "abc", branch: "w", isMain: false, kind: .sibling)
        let detached = Worktree(path: "/tmp/d", repoPath: "/tmp/alpha", head: "abc", branch: nil, isMain: false, kind: .sibling)
        let cases: [(Worktree, WorktreeState)] = [
            (branch, WorktreeState(changedFiles: 3)),
            (branch, WorktreeState(hasSubmodules: true, submodulePaths: nil)),
            (detached, WorktreeState(localOnlyCommits: 2, localOnlyShas: ["a"])),
            (detached, WorktreeState(reflogOnlyCommits: 1)),
        ]
        // An incomplete search for repos inside: the list could miss one.
        let incomplete = WorktreeState(changedFiles: 1, changedPaths: [GitStatusEntry(code: "??", path: "a")],
                                       nestedSearchIncomplete: "stopped after 10 entries")
        let incompleteSafety = SafetyCheck.evaluate(worktree: branch, state: incomplete, idle: .idle(days: 40),
                                                    settings: Settings(), cwdIndex: ProcessCwdIndex(entries: []))
        #expect(RemoveAnyway.verdict(for: branch, state: incomplete, safety: incompleteSafety)
            == .unavailable(.nestedSearchIncomplete("stopped after 10 entries")))
        for (worktree, state) in cases {
            let safety = SafetyCheck.evaluate(worktree: worktree, state: state, idle: .idle(days: 40), settings: Settings(),
                                              cwdIndex: ProcessCwdIndex(entries: []))
            #expect(!safety.manualAllowed)
            guard case .unavailable(.gitError) = RemoveAnyway.verdict(for: worktree, state: state, safety: safety) else {
                Issue.record("offered for \(state)")
                continue
            }
        }
        // Consistent, the same states are offered.
        let listed = WorktreeState(changedFiles: 1, changedPaths: [GitStatusEntry(code: "??", path: "a")])
        let safety = SafetyCheck.evaluate(worktree: branch, state: listed, idle: .idle(days: 40), settings: Settings(),
                                          cwdIndex: ProcessCwdIndex(entries: []))
        #expect(RemoveAnyway.verdict(for: branch, state: listed, safety: safety).lossList != nil)
    }

    /// A stale record (the folder's `.git` leads to another repo) is never offered either.
    @Test func aStaleRecordIsNeverOffered() {
        let worktree = Worktree(path: "/tmp/shared", repoPath: "/tmp/alpha", head: "abc", branch: "x", isMain: false, kind: .sibling)
        let state = WorktreeState(changedFiles: 1, changedPaths: [GitStatusEntry(code: "??", path: "a")],
                                  staleRecord: "/tmp/bravo/.git/worktrees/shared")
        let safety = SafetyCheck.evaluate(worktree: worktree, state: state, idle: .idle(days: 40), settings: Settings(),
                                          cwdIndex: ProcessCwdIndex(entries: []))
        #expect(RemoveAnyway.verdict(for: worktree, state: state, safety: safety) == .unavailable(.staleRecord(leadsTo: "/tmp/bravo/.git/worktrees/shared")))
    }

    enum Change: String, CaseIterable {
        case newUntrackedFile, editedPath, sneakyEdit, newCommitDetached, newNestedRepo, processInside, lock, rebaseStarted,
             branchRenamed, workGone
    }

    /// Between the confirmation and the delete, each change makes the re-check refuse: "It changed since you
    /// confirmed", with the worktree and its files left as they were.
    @Test(arguments: Change.allCases)
    func aChangeSinceTheConfirmationIsRefused(_ change: Change) async throws {
        let world = try await RemoveAnywayWorld.make()
        defer { world.remove() }
        let fixture = world.fixture
        let target: URL
        if change == .newCommitDetached {
            target = try await fixture.addWorktree(to: world.repo, at: world.repo.deletingLastPathComponent()
                .appending(path: "alpha-detached"), detached: true)
            try fixture.write("one\n", to: "one.txt", in: target)
            try await fixture.commitAll(in: target, message: "One")
        } else {
            target = try await world.safety.sibling("target")
        }
        let draft = try fixture.write("draft\n", to: "draft.md", in: target)
        let assessment = try await world.assess(target)
        let list = try #require(assessment.removeAnyway.lossList, "\(change)")
        var removeIndex: ProcessCwdIndex? = ProcessCwdIndex(entries: [])
        let sleeper = SleepingProcess()
        defer { sleeper.stop() }

        switch change {
        case .newUntrackedFile:
            try fixture.write("more\n", to: "second.md", in: target)
        case .editedPath:
            try fixture.write("tracked edit\n", to: "README.md", in: target)
        case .sneakyEdit:
            // The same path, still untracked, its date put back: only its size tells.
            let date = try #require(try FileManager.default.attributesOfItem(atPath: draft.path)[.modificationDate] as? Date)
            try fixture.write("draft, longer now\n", to: "draft.md", in: target)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: draft.path)
        case .newCommitDetached:
            try fixture.write("two\n", to: "two.txt", in: target)
            try await fixture.run(["add", "two.txt"], in: target)
            try await fixture.run(["commit", "--quiet", "-m", "Two"], in: target)
        case .newNestedRepo:
            let inner = target.appending(path: "node_modules/fresh")
            try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
            try await fixture.run(["init", "--quiet", inner.path], in: fixture.url)
            try fixture.write("x\n", to: "x.txt", in: inner)
        case .processInside:
            try sleeper.start(in: target)
            removeIndex = nil  // the real lsof, as in the app
        case .lock:
            try await fixture.lock(target, in: world.repo)
        case .rebaseStarted:
            let marker = try await world.gitDir(of: target).appending(path: "rebase-merge")
            try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: true)
        case .branchRenamed:
            // The list is the same; git's record of the worktree is not.
            try await fixture.run(["branch", "-m", "target", "renamed"], in: target)
        case .workGone:
            // Nothing blocks a plain removal now: Remove anyway (and its --force) is not for it any more.
            try FileManager.default.moveItem(at: draft, to: fixture.url.appending(path: "saved-draft.md"))
        }

        await #expect("\(change)") {
            try await world.remover(cwdIndex: removeIndex).removeAnyway(
                assessment.worktree, confirmed: list, expectation: RemovalExpectation(assessment: assessment),
                estimatedBytes: nil, knownWorktrees: try await world.known()
            )
        } throws: { error in
            guard let mismatch = error as? RemovalExpectation.Mismatch else { return false }
            return !mismatch.changes.isEmpty
        }
        #expect(world.removeCalls.isEmpty, "\(change)")
        #expect(FileManager.default.fileExists(atPath: change == .workGone ? target.path : draft.path), "\(change)")
        #expect(try world.log.entries().isEmpty)
    }

    /// The sneaky edit is caught by the list alone (the idle clock doesn't see it): the stamp differs.
    @Test func anEditKeepingTheDateIsAChangeInTheList() async throws {
        let world = try await RemoveAnywayWorld.make()
        defer { world.remove() }
        let target = try await world.safety.sibling("target")
        let draft = try world.fixture.write("draft\n", to: "draft.md", in: target)
        let before = try #require(try await world.assess(target).removeAnyway.lossList)
        let date = try #require(try FileManager.default.attributesOfItem(atPath: draft.path)[.modificationDate] as? Date)
        try world.fixture.write("draft, longer now\n", to: "draft.md", in: target)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: draft.path)
        let after = try #require(try await world.assess(target).removeAnyway.lossList)
        #expect(after.changes(since: before) == ["Uncommitted or untracked files: changed: draft.md."])
        #expect(before.changes(since: before).isEmpty)
    }

    /// Auto mode never removes a blocked worktree, Remove anyway or not, and never passes `--force`.
    @Test func autoModeNeverRemovesABlockedWorktree() async throws {
        let world = try await RemoveAnywayWorld.make()
        defer { world.remove() }
        let idle = try await world.safety.sibling("idle")
        let dirty = try await world.safety.sibling("dirty")
        try world.fixture.write("work\n", to: "work.txt", in: dirty)
        let environment = world.fixture.environment(clockOffset: 40 * 86_400)
        let settings = Settings(autoEnabled: true, autoEnabledAt: environment.now())
        let assessor = WorktreeAssessor(git: world.fixture.git, settings: settings, environment: environment)
        let rows = await assessor.assess(try await world.known(), cwdIndex: ProcessCwdIndex(entries: []))
        #expect(rows.first { $0.worktree.branch == "dirty" }?.removeAnyway.lossList != nil, "offered by hand")

        let plan = AutoPlanner.plan(rows, settings: settings, now: environment.now())
        #expect(plan.remove.map(\.worktree.branch) == ["idle"])
        var remover = Remover(git: world.spy.git, settings: settings, environment: environment)
        remover.captureCwdIndex = { ProcessCwdIndex(entries: []) }
        let outcome = await AutoRunner(remover: remover).run(plan, ignoringReportOnly: true)
        #expect(outcome.removed.map(\.entry.branch) == ["idle"])
        #expect(!FileManager.default.fileExists(atPath: idle.path))
        #expect(FileManager.default.fileExists(atPath: dirty.appending(path: "work.txt").path))
        #expect(world.removeCalls.count == 1 && world.removeCalls.allSatisfy { !$0.contains("--force") }, "\(world.removeCalls)")
        #expect(try world.log.entries().allSatisfy { $0.action == .worktreeRemove && $0.mode == .auto })
    }
}
