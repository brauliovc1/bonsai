@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// The wave-3 review's light-clean findings (r1, r2, r6 and items 6–7), each with the safe outcome.
@Suite("Light clean: wave-3 review")
struct LightCleanReviewTests {
    // r1 / item 1: run inside `dist`, `check-ignore -q .` applied dist's own `.gitignore` to dist itself.
    @Test func aFoldersOwnGitignoreDoesNotMakeItIgnored() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "r1")
        try world.fixture.write("*\n!.gitignore\n!notes.md\n", to: "dist/.gitignore", in: wt)
        try world.fixture.write("my hand-written notes\n", to: "dist/notes.md", in: wt)
        try world.file("dist/bundle.js", in: wt)

        let findings = await world.finder().candidates(in: try await world.worktree(wt))

        #expect(findings.candidates.isEmpty, "\(findings)")
        #expect(findings.skipped == [LightCleanSkip(relativePath: "dist", name: "dist", reason: .notIgnored)])
        #expect(world.exists("dist/notes.md", in: wt))
    }

    @Test func aFolderIgnoredFromItsParentStillIsACandidateWithItsOwnGitignore() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "own")
        try world.file(".next/cache/x.bin", in: wt)
        try world.fixture.write(LightCleanWorld.gitignore + ".next/\n", to: ".gitignore", in: wt)
        try await world.fixture.commitAll(in: wt, message: "Ignore .next")
        try world.fixture.write("*\n", to: ".next/.gitignore", in: wt)

        let findings = await world.finder().candidates(in: try await world.worktree(wt))
        #expect(findings.candidates.map(\.relativePath) == [".next"], "\(findings)")
    }

    // r2 / item 2: `ls-files` inside `build` missed the tracked `Build/config.txt` (case-insensitive APFS).
    @Test func aTrackedFileInADifferentCaseKeepsTheFolder() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "r2")
        try #require(FileManager.default.fileExists(atPath: wt.appending(path: "readme.MD").path), "needs a case-insensitive volume")
        try world.fixture.write(LightCleanWorld.gitignore + "build/\n", to: ".gitignore", in: wt)
        try world.fixture.write("v1\n", to: "build/config.txt", in: wt)
        try await world.fixture.run(["add", ".gitignore"], in: wt)
        try await world.fixture.run(["add", "-f", "build/config.txt"], in: wt)
        try await world.fixture.run(["mv", "build/config.txt", "Build/config.txt"], in: wt)
        try await world.fixture.run(["commit", "--quiet", "-m", "track Build/config.txt"], in: wt)
        try world.fixture.write("v2 local edit\n", to: "build/config.txt", in: wt)
        try world.file("build/out.o", in: wt)

        let findings = await world.finder().candidates(in: try await world.worktree(wt))

        #expect(findings.candidates.isEmpty, "\(findings)")
        #expect(findings.skipped == [LightCleanSkip(relativePath: "build", name: "build", reason: .hasTrackedFiles)])
        #expect(try String(contentsOf: wt.appending(path: "build/config.txt"), encoding: .utf8) == "v2 local edit\n")
    }

    // Item 2's extra guard: git doesn't apply `:(icase)` to the parent's prefix, so a parent folder whose
    // case differs from the index hides the tracked file from `ls-files`; `git status` still lists the edit.
    @Test func anEditGitStatusListsKeepsTheFolderWhenLsFilesMissesIt() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "parentcase")
        try #require(FileManager.default.fileExists(atPath: wt.appending(path: "readme.MD").path), "needs a case-insensitive volume")
        try world.fixture.write(LightCleanWorld.gitignore + "build/\n", to: ".gitignore", in: wt)
        try world.fixture.write("v1\n", to: "packages/a/Build/config.txt", in: wt)
        try await world.fixture.run(["add", ".gitignore"], in: wt)
        try await world.fixture.run(["add", "-f", "packages/a/Build/config.txt"], in: wt)
        try await world.fixture.run(["commit", "--quiet", "-m", "track it"], in: wt)
        // Same folders, other case on disk: Packages/A/build.
        let fm = FileManager.default
        try fm.moveItem(at: wt.appending(path: "packages/a/Build"), to: wt.appending(path: "packages/a/build-tmp"))
        try fm.moveItem(at: wt.appending(path: "packages/a/build-tmp"), to: wt.appending(path: "packages/a/build"))
        try fm.moveItem(at: wt.appending(path: "packages/a"), to: wt.appending(path: "packages/A-tmp"))
        try fm.moveItem(at: wt.appending(path: "packages/A-tmp"), to: wt.appending(path: "packages/A"))
        try fm.moveItem(at: wt.appending(path: "packages"), to: wt.appending(path: "Packages-tmp"))
        try fm.moveItem(at: wt.appending(path: "Packages-tmp"), to: wt.appending(path: "Packages"))
        try world.fixture.write("v2 local edit\n", to: "Packages/A/build/config.txt", in: wt)

        let findings = await world.finder().candidates(in: try await world.worktree(wt))

        #expect(findings.candidates.isEmpty, "\(findings)")
        #expect(findings.skipped.map(\.reason) == [.uncommittedFiles(["packages/a/Build/config.txt"])])
    }

    // r6 / item 5: a parent swapped for a symlink after the re-check, while lsof runs.
    @Test func aParentSwappedForASymlinkAfterTheRecheckIsRefused() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "r6")
        try world.file("packages/a/node_modules/x.js", in: wt)
        let outside = world.fixture.url.appending(path: "outside")
        try world.fixture.write("precious\n", to: "node_modules/keep.txt", in: outside)
        let worktree = try await world.worktree(wt)
        let findings = await world.finder().candidates(in: worktree)
        try #require(findings.candidates.map(\.relativePath) == ["packages/a/node_modules"])
        var cleaner = world.cleaner()
        let a = wt.appending(path: "packages/a")
        cleaner.afterRecheck = { _ in
            try? FileManager.default.moveItem(at: a, to: wt.appending(path: "packages/a-old"))
            try? FileManager.default.createSymbolicLink(at: a, withDestinationURL: outside)
        }

        let result = try await cleaner.clean(worktree, candidates: findings.candidates)

        #expect(result.deleted.isEmpty && result.entries.isEmpty)
        #expect(result.refused.map(\.reason) == [.notACandidate("packages/a is not a plain folder")])
        #expect(world.exists("node_modules/keep.txt", in: outside))
    }

    @Test func aFolderReplacedAfterTheRecheckIsRefused() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "swap")
        try world.file("node_modules/x.js", in: wt)
        let worktree = try await world.worktree(wt)
        let findings = await world.finder().candidates(in: worktree)
        var cleaner = world.cleaner()
        let fixture = world.fixture
        cleaner.afterRecheck = { _ in
            try? FileManager.default.moveItem(at: wt.appending(path: "node_modules"), to: wt.appending(path: "moved-away"))
            _ = try? fixture.write("someone else's\n", to: "node_modules/new.txt", in: wt)
        }

        let result = try await cleaner.clean(worktree, candidates: findings.candidates)

        #expect(result.refused.map(\.reason) == [.notACandidate("it was replaced after it was checked")])
        #expect(world.exists("node_modules/new.txt", in: wt))
    }

    // Item 6: every git call gets `-c core.fsmonitor=false`, so a repo's fsmonitor hook never runs.
    @Test func noFsmonitorHookRunsDuringAFind() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "hook")
        try world.file("node_modules/x.js", in: wt)
        let marker = world.fixture.url.appending(path: "hook-ran")
        let hook = try world.fixture.write("#!/bin/sh\ntouch '\(marker.path)'\nexit 1\n", to: "hook.sh", in: world.fixture.url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        try await world.fixture.run(["config", "core.fsmonitor", hook.path], in: world.repo)

        let findings = await world.finder().candidates(in: try await world.worktree(wt))

        #expect(findings.candidates.map(\.relativePath) == ["node_modules"])
        #expect(!FileManager.default.fileExists(atPath: marker.path), "the fsmonitor hook ran")
    }

    // Item 7: an inherited GIT_INDEX_FILE (or GIT_DIR, ...) never reaches git.
    @Test func anInheritedGitIndexFileIsIgnored() async throws {
        let world = try await LightCleanWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addSiblingWorktree(to: world.repo, name: "env")
        try world.file("node_modules/vendored.js", in: wt)
        try await world.fixture.run(["add", "-f", "node_modules/vendored.js"], in: wt)
        try await world.fixture.commitAll(in: wt, message: "Vendor one file")
        var finder = world.finder()
        // As if Bonsai were started from a git hook with another index.
        finder.git.inheritedEnvironment = ProcessInfo.processInfo.environment
            .merging(["GIT_INDEX_FILE": world.fixture.url.appending(path: "no-such-index").path]) { _, new in new }

        let findings = await finder.candidates(in: try await world.worktree(wt))

        #expect(findings.candidates.isEmpty, "\(findings)")
        #expect(findings.skipped.map(\.reason) == [.hasTrackedFiles])
    }

    @Test func processRunnerDropsInheritedVariablesByPrefix() async throws {
        let result = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [],
            environmentAdditions: ["GIT_CONFIG_NOSYSTEM": "1"],
            removingInherited: ["GIT_"],
            inheritedEnvironment: ["GIT_DIR": "/elsewhere", "GIT_INDEX_FILE": "/x", "KEEP": "yes"]
        )
        let lines = Set(result.stdoutString.split(separator: "\n").map(String.init))
        #expect(lines.contains("KEEP=yes"))
        #expect(lines.contains("GIT_TERMINAL_PROMPT=0") && lines.contains("GIT_CONFIG_NOSYSTEM=1"))
        #expect(!lines.contains { $0.hasPrefix("GIT_DIR=") || $0.hasPrefix("GIT_INDEX_FILE=") })
        #expect(Git.fixedArguments == ["-c", "core.fsmonitor=false"])
    }
}
