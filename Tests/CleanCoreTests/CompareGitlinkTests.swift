import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Compare committed submodule versions")
struct CompareGitlinkTests {
    @Test func pointerChangesAreListedWithoutReadingNestedGitConfig() async throws {
        let f = try GitFixture(); defer { f.remove() }
        let repo = try await f.makeRepo("parent")
        let dependency = try await f.makeRepo("dependency")
        let beforeSHA = try await f.run(["rev-parse", "HEAD"], in: dependency)
        try f.write("Version two\n", to: "README.md", in: dependency)
        try await f.commitAll(in: dependency)
        let afterSHA = try await f.run(["rev-parse", "HEAD"], in: dependency)
        try f.write("[submodule \"module\"]\npath = module\nurl = ../dependency\n", to: ".gitmodules", in: repo)
        try await f.run(["add", ".gitmodules"], in: repo)
        try await f.run(["update-index", "--add", "--cacheinfo", "160000,\(beforeSHA),module"], in: repo)
        try await f.run(["commit", "--quiet", "-m", "Pin dependency"], in: repo)
        let work = try await f.addSiblingWorktree(to: repo, name: "feature")
        try await f.run(["update-index", "--cacheinfo", "160000,\(afterSHA),module"], in: work)
        try await f.run(["commit", "--quiet", "-m", "Update dependency"], in: work)

        // An object-only diff must not inspect this nested checkout or run its configured helper.
        let nested = work.appending(path: "module")
        try await f.run(["init", "--quiet"], in: nested)
        let sentinel = f.url.appending(path: "nested-helper-ran")
        let script = f.url.appending(path: "nested-helper.sh")
        try Data("#!/bin/sh\n/usr/bin/touch '\(sentinel.path)'\nexit 0\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        try await f.run(["config", "core.fsmonitor", script.path], in: nested)
        let directory = repo.appending(path: ".git")
        let before = try GitMetadataSnapshot(directory: directory)
        let reader = CompareReader(git: try GitReadOnly(repository: repo, executable: f.git.executable, timeout: TestWait.limit))
        let snapshot = try await reader.load(base: "main", compare: .ref("feature"))
        let file = try #require(snapshot.files.first { $0.path == "module" })
        #expect(file.status == .modified && file.oldMode == "160000" && file.newMode == "160000")
        #expect(file.additions == 1 && file.deletions == 1)
        _ = try await reader.fileDetails(file, range: snapshot.range)
        let patch = String(decoding: try await reader.patch(file: file, range: snapshot.range), as: UTF8.self)
        #expect(patch.contains("-Subproject commit " + beforeSHA))
        #expect(patch.contains("+Subproject commit " + afterSHA))
        #expect(!FileManager.default.fileExists(atPath: sentinel.path))
        #expect(try GitMetadataSnapshot(directory: directory) == before)

        let working = try await reader.load(base: "main", compare: .worktree(work.path))
        #expect(!working.files.contains { $0.path == "module" })
        #expect(!FileManager.default.fileExists(atPath: sentinel.path))
        #expect(try GitMetadataSnapshot(directory: directory) == before)
    }
}
