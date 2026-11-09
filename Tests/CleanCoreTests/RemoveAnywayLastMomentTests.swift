@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// P12b review (P1): the fast, volatile facts are read once more after the slow inspection and the process check,
/// immediately before git; and (P2) the files of an uninitialized submodule folder are listed and checked again.
/// Cases run one at a time: each builds real repos, and together they load the machine past what the timing tests
/// (ProcessRunner, lock timeouts) tolerate.
@Suite("Remove anyway: the last moment", .serialized)
struct RemoveAnywayLastMomentTests {
    enum During: String, CaseIterable {
        case rebaseStarted, fileWritten, both, listedFileEdited
        /// An ignored `.env`: only listing the ignored files again sees it.
        case ignoredFileWritten
        /// Only for the submodule world: a file appears in the uninitialized submodule's folder.
        case submoduleFileWritten
    }

    /// A git that, right after the first time it lists the ignored files (in the middle of the re-check's slow
    /// inspection, after its `git status`, operation markers and ignored listing), does what `during` says, as another
    /// process could.
    /// `onListing`: which ignored listing it acts after (1: the slow inspection's; 2: the last-moment check's own).
    private func triggerGit(_ fixture: GitFixture, worktree: URL, gitDir: URL, _ during: During, onListing: Int = 1) throws -> Git {
        let folder = fixture.url.appending(path: "trigger-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fired = folder.appending(path: "fired")
        let rebase = "mkdir -p '\(gitDir.path)/rebase-merge'"
        let write = "printf 'written during the re-check\\n' > '\(worktree.path)/late.txt'"
        let edit = "printf 'draft, edited during the re-check\\n' > '\(worktree.path)/draft.md'"
        let submodule = "printf 'late\\n' > '\(worktree.path)/libs/library/Late.swift'"
        let env = "printf 'API_KEY=written-during-the-recheck\\n' > '\(worktree.path)/.env'"
        let action = switch during {
        case .rebaseStarted: rebase
        case .fileWritten: write
        case .both: rebase + "\n      " + write
        case .listedFileEdited: edit
        case .submoduleFileWritten: submodule
        case .ignoredFileWritten: env
        }
        let text = """
            #!/bin/sh
            '\(fixture.git.executable.path)' "$@"
            rc=$?
            case "$*" in
              *--others*--ignored*)
                printf 'x\\n' >> '\(fired.path)'
                if [ "$(wc -l < '\(fired.path)' | tr -d ' ')" = '\(onListing)' ]; then
                  \(action)
                fi ;;
            esac
            exit $rc

            """
        let script = folder.appending(path: "git")
        try Data(text.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        var git = fixture.git
        git.executable = script
        return git
    }

    @Test(arguments: [During.rebaseStarted, .fileWritten, .both, .listedFileEdited, .ignoredFileWritten])
    func aChangeDuringTheRecheckIsCaught(_ during: During) async throws {
        let world = try await RemoveAnywayWorld.make()
        defer { world.remove() }
        let wt = try await world.safety.sibling("dirty")
        try world.fixture.write("draft\n", to: "draft.md", in: wt)
        let assessment = try await world.assess(wt)
        let list = try #require(assessment.removeAnyway.lossList)
        var remover = Remover(git: try triggerGit(world.fixture, worktree: wt, gitDir: try await world.gitDir(of: wt), during),
                              settings: Settings(), environment: world.fixture.environment())
        remover.captureCwdIndex = { ProcessCwdIndex(entries: []) }

        await #expect("\(during)") {
            try await remover.removeAnyway(
                assessment.worktree, confirmed: list, expectation: RemovalExpectation(assessment: assessment),
                estimatedBytes: nil, knownWorktrees: try await world.known()
            )
        } throws: { error in
            (error as? RemovalExpectation.Mismatch)?.changes.isEmpty == false
        }
        #expect(FileManager.default.fileExists(atPath: wt.appending(path: "draft.md").path), "\(during)")
        #expect(try world.log.entries().isEmpty)
    }

    /// Files a person put in an uninitialized submodule's folder: git doesn't see them, the list does.
    @Test func filesInAnUninitializedSubmoduleFolderAreListedAndChecked() async throws {
        let world = try await RemoveAnywayWorld.make()
        defer { world.remove() }
        let fixture = world.fixture
        let (library, _) = try await fixture.xcodePackage("library", in: fixture.url, base: "libraries")
        try await fixture.run(["-c", "protocol.file.allow=always", "submodule", "add", "--quiet", library.path, "libs/library"],
                              in: world.repo)
        try await fixture.run(["commit", "--quiet", "-m", "Add a submodule"], in: world.repo)
        try await fixture.run(["push", "--quiet", "origin", "main"], in: world.repo)
        let wt = try await world.safety.sibling("subs")
        try fixture.write("my patch\n", to: "libs/library/MyPatch.swift", in: wt)
        try fixture.write("notes\n", to: "libs/library/Docs/notes.md", in: wt)

        let assessment = try await world.assess(wt)
        let list = try #require(assessment.removeAnyway.lossList, "\(assessment.removeAnyway)")
        #expect(list.plain[.submodules] == ["libs/library"])
        #expect(list.plain[.submoduleFiles] == ["libs/library/Docs/notes.md", "libs/library/MyPatch.swift"])
        #expect(list.summary.contains("2 files in submodule folders"))

        // Changed after the confirmation: refused by the last-moment check.
        try fixture.write("my patch, longer\n", to: "libs/library/MyPatch.swift", in: wt)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3_600)],
                                              ofItemAtPath: wt.appending(path: "libs/library/MyPatch.swift").path)
        await #expect(throws: RemovalExpectation.Mismatch.self) {
            try await world.remover().removeAnyway(
                assessment.worktree, confirmed: list, expectation: RemovalExpectation(assessment: assessment),
                estimatedBytes: nil, knownWorktrees: try await world.known()
            )
        }
        #expect(FileManager.default.fileExists(atPath: wt.appending(path: "libs/library/MyPatch.swift").path))

        // Confirmed as listed: removed, and the log names the files.
        let fresh = try await world.assess(wt)
        let confirmed = try #require(fresh.removeAnyway.lossList)
        let result = try await world.remover().removeAnyway(
            fresh.worktree, confirmed: confirmed, expectation: RemovalExpectation(assessment: fresh),
            estimatedBytes: nil, knownWorktrees: try await world.known()
        )
        #expect(result.entry.notes.contains("  libs/library/MyPatch.swift"))
        #expect(!FileManager.default.fileExists(atPath: wt.path))
    }

    /// The most volatile facts are read last in the last-moment check: a change right after its own ignored listing is
    /// still caught.
    @Test(arguments: [During.rebaseStarted, .fileWritten])
    func aChangeAfterTheLastMomentListingIsCaught(_ during: During) async throws {
        let world = try await RemoveAnywayWorld.make()
        defer { world.remove() }
        let wt = try await world.safety.sibling("dirty")
        try world.fixture.write("draft\n", to: "draft.md", in: wt)
        let assessment = try await world.assess(wt)
        let list = try #require(assessment.removeAnyway.lossList)
        let git = try triggerGit(world.fixture, worktree: wt, gitDir: try await world.gitDir(of: wt), during, onListing: 2)
        var remover = Remover(git: git, settings: Settings(), environment: world.fixture.environment())
        remover.captureCwdIndex = { ProcessCwdIndex(entries: []) }

        await #expect("\(during)") {
            try await remover.removeAnyway(
                assessment.worktree, confirmed: list, expectation: RemovalExpectation(assessment: assessment),
                estimatedBytes: nil, knownWorktrees: try await world.known()
            )
        } throws: { error in
            (error as? RemovalExpectation.Mismatch)?.changes.isEmpty == false
        }
        #expect(FileManager.default.fileExists(atPath: wt.appending(path: "draft.md").path))
        #expect(try world.log.entries().isEmpty)
    }

    enum Moved: String, CaseIterable {
        /// A commit on a detached HEAD: `git status` stays the same, the commit would be lost unlisted.
        case detachedCommit
        /// Another branch at the same commit checked out.
        case branchSwitched
    }

    /// HEAD or the branch changed after the slow inspection read them: only the last-moment check sees it.
    @Test(arguments: Moved.allCases)
    func headMovedDuringTheRecheckIsCaught(_ moved: Moved) async throws {
        let world = try await RemoveAnywayWorld.make()
        defer { world.remove() }
        let fixture = world.fixture
        let wt = moved == .detachedCommit
            ? try await fixture.addWorktree(to: world.repo, at: world.repo.deletingLastPathComponent()
                .appending(path: "alpha-detached"), detached: true)
            : try await world.safety.sibling("target")
        try fixture.write("draft\n", to: "draft.md", in: wt)
        let assessment = try await world.assess(wt)
        let list = try #require(assessment.removeAnyway.lossList, "\(assessment.removeAnyway)")
        var remover = world.remover()
        remover.afterInspection = {
            switch moved {
            case .detachedCommit:
                _ = try? fixture.write("late\n", to: "late.txt", in: wt)
                _ = try? await fixture.run(["add", "late.txt"], in: wt)
                _ = try? await fixture.run(["commit", "--quiet", "-m", "Late"], in: wt)
            case .branchSwitched:
                _ = try? await fixture.run(["checkout", "--quiet", "-b", "other"], in: wt)
            }
        }
        await #expect("\(moved)") {
            try await remover.removeAnyway(
                assessment.worktree, confirmed: list, expectation: RemovalExpectation(assessment: assessment),
                estimatedBytes: nil, knownWorktrees: try await world.known()
            )
        } throws: { error in
            (error as? RemovalExpectation.Mismatch)?.changes.contains { $0.hasPrefix("HEAD moved") || $0.hasPrefix("The branch is now") } == true
        }
        #expect(FileManager.default.fileExists(atPath: wt.appending(path: "draft.md").path))
        #expect(world.removeCalls.isEmpty)
    }

    /// A file put in the uninitialized submodule's folder while the slow re-check runs (after it walked that folder):
    /// only the last-moment walk sees it.
    @Test func aSubmoduleFolderFileWrittenDuringTheRecheckIsCaught() async throws {
        let world = try await RemoveAnywayWorld.make()
        defer { world.remove() }
        let fixture = world.fixture
        let (library, _) = try await fixture.xcodePackage("library", in: fixture.url, base: "libraries")
        try await fixture.run(["-c", "protocol.file.allow=always", "submodule", "add", "--quiet", library.path, "libs/library"],
                              in: world.repo)
        try await fixture.run(["commit", "--quiet", "-m", "Add a submodule"], in: world.repo)
        try await fixture.run(["push", "--quiet", "origin", "main"], in: world.repo)
        let wt = try await world.safety.sibling("subs")
        try fixture.write("my patch\n", to: "libs/library/MyPatch.swift", in: wt)
        let assessment = try await world.assess(wt)
        let list = try #require(assessment.removeAnyway.lossList)
        var remover = Remover(git: try triggerGit(fixture, worktree: wt, gitDir: try await world.gitDir(of: wt), .submoduleFileWritten),
                              settings: Settings(), environment: fixture.environment())
        remover.captureCwdIndex = { ProcessCwdIndex(entries: []) }

        await #expect {
            try await remover.removeAnyway(
                assessment.worktree, confirmed: list, expectation: RemovalExpectation(assessment: assessment),
                estimatedBytes: nil, knownWorktrees: try await world.known()
            )
        } throws: { error in
            (error as? RemovalExpectation.Mismatch)?.changes.contains { $0.contains("Late.swift") } == true
        }
        #expect(FileManager.default.fileExists(atPath: wt.appending(path: "libs/library/Late.swift").path))
    }

    /// A submodule folder that can't be listed whole makes Remove anyway unavailable.
    @Test func aSubmoduleFolderThatCanNotBeListedIsNeverOffered() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "submodule-walk-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<12 {
            try FileManager.default.createDirectory(at: root.appending(path: "libs/x/d\(index)"), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: root.appending(path: "libs/x/d\(index)/f.txt"))
        }
        let walk = SubmoduleFolderWalk.files(in: root, submodules: ["libs/x", "libs/missing"], limit: 10)
        #expect(walk.incomplete == "libs/x")
        #expect(SubmoduleFolderWalk.files(in: root, submodules: ["libs/x"]).files.count == 12)
        try FileManager.default.createDirectory(at: root.appending(path: "libs/x/.git"), withIntermediateDirectories: true)
        #expect(SubmoduleFolderWalk.files(in: root, submodules: ["libs/x"]).files.isEmpty, "initialized: not walked")

        let worktree = Worktree(path: "/tmp/w", repoPath: "/tmp/alpha", head: "abc", branch: "w", isMain: false, kind: .sibling)
        let state = WorktreeState(hasSubmodules: true, submodulePaths: ["libs/x"], submoduleFilesIncomplete: "libs/x")
        let safety = SafetyCheck.evaluate(worktree: worktree, state: state, idle: .idle(days: 40), settings: Settings(),
                                          cwdIndex: ProcessCwdIndex(entries: []))
        #expect(RemoveAnyway.verdict(for: worktree, state: state, safety: safety)
            == .unavailable(.gitError("everything in libs/x could not be listed")))
    }
}
