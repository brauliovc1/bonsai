@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// PLAN §4.8 "Remove anyway", for each blocker it may override: offered with the exact list, one
/// `git worktree remove --force <path>` (never two), the branch kept, one log entry holding the list, and
/// Restore bringing the worktree back without what was lost.
/// Cases run one at a time: each builds real repos, and together they load the machine past what the timing tests
/// (ProcessRunner, lock timeouts) tolerate.
@Suite("Remove anyway", .serialized)
struct RemoveAnywayTests {
    enum Blocker: String, CaseIterable {
        case uncommitted, hiddenEdits, repoWithLocalWork, unreadableRepo, submodules, detachedUnpushed, reflogOnly
    }

    /// Sets up a worktree blocked only by `blocker`; returns it, its branch and the list it must offer.
    private func setUp(_ blocker: Blocker, _ world: RemoveAnywayWorld) async throws
        -> (url: URL, branch: String?, expected: [LossList.Category: [String]], lost: String?) {
        let fixture = world.fixture
        switch blocker {
        case .uncommitted:
            let wt = try await world.safety.sibling("dirty")
            try fixture.write("draft\n", to: "notes/draft.md", in: wt)
            try fixture.write("changed\n", to: "README.md", in: wt)
            try fixture.write("new\n", to: "added.txt", in: wt)
            try await fixture.run(["add", "added.txt"], in: wt)
            return (wt, "dirty", [.uncommittedFiles: ["README.md (changed)", "added.txt (added)", "notes/draft.md (untracked)"]],
                    "notes/draft.md")
        case .hiddenEdits:
            let wt = try await world.safety.sibling("hidden")
            try await fixture.run(["update-index", "--assume-unchanged", "README.md"], in: wt)
            try fixture.write("my hidden edit\n", to: "README.md", in: wt)
            return (wt, "hidden", [.hiddenEdits: ["README.md"]], nil)
        case .repoWithLocalWork:
            let wt = try await world.safety.sibling("nested")
            let (clone, _) = try await fixture.xcodePackage("mylib", in: wt, base: "node_modules/vendor")
            try fixture.write("work\n", to: "Draft.swift", in: clone)
            return (wt, "nested", [.reposWithLocalWork: ["node_modules/vendor/checkouts/mylib (1 unsaved change)"]],
                    "node_modules/vendor/checkouts/mylib/Draft.swift")
        case .unreadableRepo:
            let wt = try await world.safety.sibling("unreadable")
            try await fixture.xcodePackage("sdk", in: wt, base: "node_modules/vendor", broken: true)
            return (wt, "unreadable", [.unreadableRepos: ["node_modules/vendor/checkouts/sdk (fatal: bad object HEAD)"]],
                    "node_modules/vendor/checkouts/sdk/Package.swift")
        case .submodules:
            let (library, _) = try await fixture.xcodePackage("library", in: fixture.url, base: "libraries")
            try await fixture.run(["-c", "protocol.file.allow=always", "submodule", "add", "--quiet", library.path, "libs/library"],
                                  in: world.repo)
            try await fixture.run(["commit", "--quiet", "-m", "Add a submodule"], in: world.repo)
            try await fixture.run(["push", "--quiet", "origin", "main"], in: world.repo)
            let wt = try await world.safety.sibling("subs")
            return (wt, "subs", [.submodules: ["libs/library"]], nil)
        case .detachedUnpushed:
            let wt = try await fixture.addWorktree(to: world.repo, at: world.repo.deletingLastPathComponent()
                .appending(path: "alpha-detached"), detached: true)
            try fixture.write("experiment\n", to: "experiment.txt", in: wt)
            try await fixture.commitAll(in: wt, message: "Experiment")
            let sha = try await fixture.run(["rev-parse", "HEAD"], in: wt)
            let short = String(sha.prefix(12))
            // Restore checks out that very commit (git hasn't collected it yet), so no file is gone for good here.
            return (wt, nil, [.unpushedCommits: [short], .unreachableCommits: [short]], nil)
        case .reflogOnly:
            let wt = try await fixture.addWorktree(to: world.repo, at: world.repo.deletingLastPathComponent()
                .appending(path: "alpha-reflog"), detached: true)
            try fixture.write("tried\n", to: "tried.txt", in: wt)
            try await fixture.commitAll(in: wt, message: "Tried something")
            let sha = try await fixture.run(["rev-parse", "HEAD"], in: wt)
            try await fixture.run(["checkout", "--quiet", "--detach", "HEAD~1"], in: wt)
            return (wt, nil, [.unreachableCommits: [String(sha.prefix(12))]], "tried.txt")
        }
    }

    @Test(arguments: Blocker.allCases)
    func removesOneBlockedWorktreeWithOneForce(_ blocker: Blocker) async throws {
        let world = try await RemoveAnywayWorld.make()
        defer { world.remove() }
        let (wt, branch, expected, lost) = try await setUp(blocker, world)
        let assessment = try await world.assess(wt)
        #expect(!assessment.safety.manualAllowed, "\(blocker) must block: \(assessment.safety)")
        let list = try #require(assessment.removeAnyway.lossList, "\(blocker): \(assessment.removeAnyway)")
        // Only the lost categories are compared here: notes (Claude session, stashes) don't apply.
        #expect(list.plain.filter { $0.key.isLost } == expected, "\(blocker)")

        // The usual removal still refuses it.
        await #expect(throws: RemovalError.self) {
            try await world.remover().remove(assessment.worktree, mode: .manual, estimatedBytes: nil)
        }
        #expect(world.removeCalls.isEmpty)

        let result = try await world.remover().removeAnyway(
            assessment.worktree, confirmed: list, expectation: RemovalExpectation(assessment: assessment),
            estimatedBytes: 1234, knownWorktrees: try await world.known()
        )
        #expect(!FileManager.default.fileExists(atPath: wt.path))
        let calls = world.removeCalls
        #expect(calls.count == 1)
        #expect(calls.first?.filter { $0 == "--force" }.count == 1, "exactly one --force: \(calls)")
        #expect(calls.first?.suffix(3) == ["remove", "--force", assessment.worktree.path], "\(calls)")
        if let branch { #expect(await world.branchExists(branch)) }

        let entries = try world.log.entries()
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry == result.entry)
        #expect(entry.action == .worktreeRemoveAnyway && entry.mode == .manual)
        #expect(entry.notes == list.logNotes)
        #expect(entry.notes.first == list.summary && list.summary.hasPrefix("Lost: "))
        #expect(entry.headSha == assessment.worktree.head && entry.branch == branch && entry.estimatedBytes == 1234)
        #expect(entry.isRestorable)

        let restored = try await Restorer(git: world.fixture.git, environment: world.fixture.environment()).restore(entryID: entry.id)
        #expect(FileManager.default.fileExists(atPath: wt.appending(path: ".git").path))
        #expect(restored.note.hasPrefix(Restorer.lostFilesNote))
        if let lost {
            #expect(!FileManager.default.fileExists(atPath: wt.appending(path: lost).path), "\(lost) came back")
        }
        if blocker == .hiddenEdits {
            #expect(try String(contentsOf: wt.appending(path: "README.md"), encoding: .utf8) != "my hidden edit\n")
        }
        #expect(try world.log.entries().first?.restoredAt != nil)
    }

    /// The notes listed with it (§4.8): ignored files are deleted, stashes and branch commits are kept, a Claude
    /// session can't continue.
    @Test func theNotesAreListedToo() async throws {
        let world = try await RemoveAnywayWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addClaudeWorktree(to: world.repo, name: "session")
        try world.fixture.write("SECRET=1\n", to: ".env", in: wt)
        try world.fixture.write("stash me\n", to: "README.md", in: wt)
        try await world.fixture.run(["stash", "push", "--quiet"], in: wt)
        try world.fixture.write("committed\n", to: "work.txt", in: wt)
        try await world.fixture.commitAll(in: wt, message: "Local commit")
        try world.fixture.write("draft\n", to: "draft.md", in: wt)

        let list = try #require(try await world.assess(wt).removeAnyway.lossList)
        #expect(list.plain == [
            .uncommittedFiles: ["draft.md (untracked)"],
            .ignoredFiles: [".env"],
            .commitsOnBranch: ["1 commit not pushed on claude/session"],
            .stashes: ["1 stash made on this branch"],
            .claudeSession: [SafetyReason.claudeSessionWarning],
        ])
        #expect(list.summary == "Lost: 1 uncommitted file, 1 ignored file.")
        #expect(list.lostSections.map(\.category) == [.uncommittedFiles, .ignoredFiles])
    }

    /// The log keeps at most 200 entries and counts the rest.
    @Test func theLogKeepsTwoHundredEntries() {
        let entries = (0..<250).map { LossList.Entry(text: "file\($0).txt", detail: "untracked", key: "??") }
        let list = LossList(sections: [LossList.Section(category: .uncommittedFiles, entries: entries)])
        let notes = list.logNotes
        #expect(notes.first == "Lost: 250 uncommitted files.")
        #expect(notes[1] == "Uncommitted or untracked files (250):")
        #expect(notes.filter { $0.hasPrefix("  file") }.count == 200)
        #expect(notes.last == "and 50 more")
    }
}
