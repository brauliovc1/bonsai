import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Compare read-only boundary")
struct CompareReadOnlyTests {
    @Test func refusesWritesAndOutputFlags() async throws {
        for command in ["fetch", "checkout", "update-ref", "merge", "rebase", "reset", "stash", "branch", "gc", "config"] {
            #expect(!GitReadOnly.permits([command]))
        }
        for args in [["worktree", "remove", "/tmp/x"], ["diff", "--output=/tmp/sentinel"], ["log", "--output=/tmp/sentinel"],
                     ["show", "--textconv"], ["diff", "--ext-diff"], ["symbolic-ref", "HEAD", "refs/heads/other"]] {
            #expect(!GitReadOnly.permits(args))
        }
        let f = try GitFixture(); defer { f.remove() }
        let repo = try await f.makeRepo("refusal")
        let git = try GitReadOnly(repository: repo, executable: f.git.executable)
        await #expect(throws: CompareError.self) { try await git.data(["fetch"]) }
    }

    @Test func everyCoreReadPreservesMetadata() async throws {
        let world = try await CompareFixture.make(); defer { world.fixture.remove() }
        let directory = world.repo.appending(path: ".git")
        let before = try GitMetadataSnapshot(directory: directory)
        let reader = try world.reader()
        _ = try await RefCatalog.load(using: reader.git)
        #expect(try GitMetadataSnapshot(directory: directory) == before)
        let result = try await reader.load(base: "main", compare: .ref("feature/welcome"))
        #expect(try GitMetadataSnapshot(directory: directory) == before)
        for file in result.files {
            _ = try await reader.fileDetails(file, range: result.range)
            let patch = try await reader.patch(file: file, range: result.range)
            if file.additions > 0 { #expect(!DiffParser.parse(patch).hunks.isEmpty, "\(file.path)") }
            #expect(try GitMetadataSnapshot(directory: directory) == before)
        }
        _ = try await reader.patch(file: nil, range: result.range)
        let commit = try #require(result.range.commits.first)
        let range = try await reader.commitRange(commit, original: result.range)
        _ = try await reader.files(from: range.mergeBase, to: range.compareSHA)
        #expect(try GitMetadataSnapshot(directory: directory) == before)
    }

    @Test func hostileHelpersNeverRun() async throws {
        let world = try await CompareFixture.make(); defer { world.fixture.remove() }
        let f = world.fixture
        let sentinel = f.url.appending(path: "helper-ran")
        let script = f.url.appending(path: "helper.sh")
        try Data("#!/bin/sh\n/usr/bin/touch '\(sentinel.path)'\nexit 0\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        try f.write("*.swift diff=hostile filter=hostile merge=hostile\n", to: ".gitattributes", in: world.repo)
        try await f.commitAll(in: world.repo)
        try f.write("*.swift diff=hostile filter=hostile merge=hostile\n", to: ".gitattributes", in: world.worktree)
        for key in ["diff.external", "diff.hostile.textconv", "core.fsmonitor", "filter.hostile.clean", "filter.hostile.smudge", "filter.hostile.process", "merge.hostile.driver"] {
            try await f.run(["config", key, script.path], in: world.repo)
        }
        let directory = world.repo.appending(path: ".git")
        let before = try GitMetadataSnapshot(directory: directory)
        let reader = try world.reader()
        _ = try await RefCatalog.load(using: reader.git)
        let result = try await reader.load(base: "main", compare: .worktree(world.worktree.path))
        for file in result.files { _ = try await reader.patch(file: file, range: result.range) }
        #expect(!FileManager.default.fileExists(atPath: sentinel.path))
        #expect(try GitMetadataSnapshot(directory: directory) == before)
    }

    @Test func mergeConflictAndOldGit() async throws {
        let f = try GitFixture(); defer { f.remove() }
        let repo = try await f.makeRepo("conflict")
        let work = try await f.addSiblingWorktree(to: repo, name: "other")
        try f.write("base changed\n", to: "README.md", in: repo); try await f.commitAll(in: repo)
        try f.write("branch changed\n", to: "README.md", in: work); try await f.commitAll(in: work)
        let git = try GitReadOnly(repository: repo, executable: f.git.executable, timeout: TestWait.limit)
        let check = await MergeCheck.check(base: "main", compare: "other", using: git)
        #expect(check.state == .conflicts && check.files == ["README.md"])
        let oldGit = f.url.appending(path: "old-git")
        try Data("#!/bin/sh\necho 'unknown option write-tree; Git 2.38 is needed' >&2\nexit 129\n".utf8).write(to: oldGit)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: oldGit.path)
        let old = try GitReadOnly(repository: repo, executable: oldGit, timeout: TestWait.limit)
        let unavailable = await MergeCheck.check(base: "main", compare: "other", using: old)
        #expect(unavailable.state == .unavailable)
        #expect(unavailable.detail?.contains("2.38") == true)
    }
}
