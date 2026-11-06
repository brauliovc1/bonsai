@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// Git errors, nested checkouts, processes inside, and the small parsers behind the checks.
@Suite("Safety edges")
struct SafetyEdgeTests {
    @Test func brokenGitFileBlocksBoth() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("broken")
        try world.fixture.write("gitdir: /nonexistent/elsewhere\n", to: ".git", in: wt)
        let report = try await world.check(wt)
        #expect(report.blockers.contains { if case .gitError = $0 { true } else { false } }, "\(report)")
        #expect(!report.manualAllowed && !report.autoEligible)
    }

    @Test func missingGitFileNeverDescribesTheEnclosingRepo() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        // Nested in the main checkout: without its .git file, git would answer for the main repo.
        let wt = try await world.fixture.addClaudeWorktree(to: world.repo, name: "orphaned")
        let before = try await world.worktree(wt)
        try FileManager.default.removeItem(at: wt.appending(path: ".git"))
        try world.fixture.write("dirty\n", to: "dirty.txt", in: world.repo)

        // git now lists it as prunable although the folder is there.
        let report = try await world.check(wt)
        guard case .gitError(let message)? = report.blockers.first, report.blockers.count == 1 else {
            Issue.record("expected only a git error, got \(report)")
            return
        }
        #expect(message.contains("prunable") && message.contains("folder exists"))
        #expect(!report.manualAllowed && !report.autoEligible)

        // With the record from before the .git file went away, the inspector still refuses to read it.
        let state = await WorktreeInspector(git: world.fixture.git).inspect(before)
        #expect(state.changedFiles == 0)
        #expect(state.gitErrors.first?.contains("not this worktree") == true, "\(state.gitErrors)")
    }

    @Test func folderHoldingOnlyBuildOutputIsHarmlessButUserFilesInsideAreNot() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("mono")
        try world.fixture.write("x\n", to: "packages/app/node_modules/x/index.js", in: wt)
        try world.fixture.write("x\n", to: "packages/app/build.log", in: wt)
        #expect(try await world.check(wt).autoEligible)

        // git lists the collapsed folder; the whole folder goes with the worktree, so that is what is shown.
        try world.fixture.write("A=1\n", to: "packages/app/.env", in: wt)
        let report = try await world.check(wt)
        #expect(report.notes == [.ignoredUserFiles(["packages/"])], "\(report)")
        #expect(report.manualAllowed && !report.autoEligible)

        let search = IgnoredFolderSearch(limit: 1)
        #expect(search.holdsUserFiles(wt.appending(path: "packages")), "a capped search counts as user files")
        #expect(IgnoredFolderSearch.topmost(["a/", "a/b/", "a/b/c.txt", "ab/", "d.txt"]) == ["a/", "ab/", "d.txt"])
    }

    @Test func worktreeNestedInAnIgnoredFolderBlocksBoth() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let outer = try await world.sibling("outer")
        let nested = outer.appending(path: ".claude/worktrees/inner")
        try await world.fixture.addWorktree(to: world.repo, at: nested, branch: "inner")

        let report = try await world.check(outer)
        #expect(report.blockers == [.nestedCheckouts([".claude/worktrees/inner"])], "\(report)")
        #expect(!report.manualAllowed && !report.autoEligible)

        // Found on disk too, without the list of registered worktrees.
        let fromDisk = try await world.check(outer, knownWorktrees: [])
        #expect(fromDisk.blockers == [.nestedCheckouts([".claude/worktrees/inner"])])
    }

    @Test func processInsideBlocksBoth() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("busy")
        let inside = wt.appending(path: "src")
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)

        let sleeper = SleepingProcess()
        defer { sleeper.stop() }
        try sleeper.start(in: inside)

        let index = await ProcessCwdIndex.capture(lsof: world.fixture.environment().tools.lsof)
        try #require(index.isAvailable, "lsof: \(index.failure ?? "")")
        #expect(index.processes(inside: wt).map(\.pid) == [try #require(sleeper.pid)])

        let report = try await world.check(wt, cwdIndex: index)
        #expect(report.blockers.count == 1)
        guard case .inUse(let processes)? = report.blockers.first else {
            Issue.record("expected in use, got \(report)")
            return
        }
        #expect(processes.map(\.command) == ["sleep"])
        #expect(!report.manualAllowed && !report.autoEligible)
        #expect(report.status == .inUse)
        #expect(report.status.label == "IN USE")
    }

    @Test func lsofOutputParses() {
        let output = "p420\ncloginwindow\nfcwd\nn/\np431\ncGitHub Desktop\nfcwd\nn/Users/me/My Repo\np9\nfcwd\nn/tmp\n"
        let entries = ProcessCwdIndex.parse(Data(output.utf8))
        #expect(entries == [
            .init(pid: 420, command: "loginwindow", cwd: "/"),
            .init(pid: 431, command: "GitHub Desktop", cwd: "/Users/me/My Repo"),
            .init(pid: 9, command: "", cwd: "/tmp"),
        ])
        let index = ProcessCwdIndex(entries: entries)
        #expect(index.processes(inside: URL(fileURLWithPath: "/Users/me/My Repo")).map(\.pid) == [431])
        #expect(index.processes(inside: URL(fileURLWithPath: "/Users/me/My")).isEmpty)
    }

    @Test func missingLsofIsUnavailable() async {
        let index = await ProcessCwdIndex.capture(lsof: nil)
        #expect(!index.isAvailable)
        #expect(index.failure == "lsof not found")
    }

    @Test func statusEntriesCountRenamesOnce() {
        let data = Data("R  new.txt\0old.txt\0?? untracked\0 M modified\0".utf8)
        #expect(WorktreeInspector.countStatusEntries(data) == 3)
        #expect(WorktreeInspector.countStatusEntries(Data()) == 0)
    }

    @Test func stashesCountOnlyTheirBranch() {
        let output = "WIP on feature: abc wip\nOn feature: parked\nWIP on feature-2: def x\nOn main: y\n"
        #expect(WorktreeInspector.countStashes(output, branch: "feature") == 2)
        #expect(WorktreeInspector.countStashes(output, branch: "main") == 1)
    }

    @Test func regenerableNamesFilterIgnoredEntries() {
        for harmless in ["node_modules/", "packages/web/.next/", "debug.log", "a/b/x.pyc", ".DS_Store", "next-env.d.ts"] {
            #expect(RegenerableNames.isHarmlessIgnoredPath(harmless), "\(harmless)")
        }
        for user in [".env", ".idea/", "secrets/", "build/keys.txt", "node_modules", "notes.txt"] {
            #expect(!RegenerableNames.isHarmlessIgnoredPath(user), "\(user)")
        }
    }
}
