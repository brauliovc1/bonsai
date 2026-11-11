@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Compare adversarial regressions")
struct CompareAdversarialTests {
    @Test func untrackedModesAgreeWithTheCopiedPatch() async throws {
        let f = try GitFixture(); defer { f.remove() }
        let repo = try await f.makeRepo("modes")
        try f.write("#!/bin/sh\necho inert\n", to: "executable.sh", in: repo)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: repo.appending(path: "executable.sh").path)
        try FileManager.default.createSymbolicLink(atPath: repo.appending(path: "link.txt").path, withDestinationPath: "README.md")
        let before = try GitMetadataSnapshot(directory: repo.appending(path: ".git"))
        let reader = CompareReader(git: try GitReadOnly(repository: repo, executable: f.git.executable, timeout: TestWait.limit))
        let snapshot = try await reader.load(base: "main", compare: .worktree(repo.path))
        let executable = try #require(snapshot.files.first { $0.path == "executable.sh" })
        let link = try #require(snapshot.files.first { $0.path == "link.txt" })
        #expect(executable.newMode == "100755")
        #expect(link.newMode == "120000")
        let scriptPatch = String(decoding: try await reader.patch(file: executable, range: snapshot.range), as: UTF8.self)
        let linkPatch = String(decoding: try await reader.patch(file: link, range: snapshot.range), as: UTF8.self)
        #expect(scriptPatch.contains("new file mode 100755"))
        #expect(linkPatch.contains("new file mode 120000"))
        #expect(try GitMetadataSnapshot(directory: repo.appending(path: ".git")) == before)
    }

    @Test func renamedTabbedPathsKeepBothNamesAndCounts() async throws {
        let f = try GitFixture(); defer { f.remove() }
        let repo = try await f.makeRepo("names")
        let old = "old\tname\n.txt"; let new = "new\tname\n.txt"
        try f.write((1...12).map { "line \($0)" }.joined(separator: "\n") + "\n", to: old, in: repo)
        try await f.commitAll(in: repo)
        let work = try await f.addSiblingWorktree(to: repo, name: "feature")
        try await f.run(["mv", old, new], in: work)
        try f.write((1...12).map { "line \($0)" }.joined(separator: "\n") + "\nnew line\n", to: new, in: work)
        try await f.commitAll(in: work)
        let reader = CompareReader(git: try GitReadOnly(repository: repo, executable: f.git.executable, timeout: TestWait.limit))
        let snapshot = try await reader.load(base: "main", compare: .ref("feature"))
        let file = try #require(snapshot.files.first { $0.path == new })
        #expect(file.status == .renamed && file.oldPath == old && file.additions == 1 && file.deletions == 0)
        let patch = try await reader.patch(file: file, range: snapshot.range)
        #expect(DiffParser.parse(patch).hunks.first?.lines.contains { $0.text == "new line" } == true)
    }

    @Test func untrackedSymlinkStaysInertAndOutsideContentsNeverEnterPatch() async throws {
        let f = try GitFixture(); defer { f.remove() }
        let repo = try await f.makeRepo("link")
        let outside = f.url.appending(path: "outside.txt")
        try Data("outside-secret-never-read".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: repo.appending(path: "outside-link"), withDestinationURL: outside)
        let reader = CompareReader(git: try GitReadOnly(repository: repo, executable: f.git.executable, timeout: TestWait.limit))
        let snapshot = try await reader.load(base: "main", compare: .worktree(repo.path))
        let file = try #require(snapshot.files.first { $0.path == "outside-link" })
        let patch = String(decoding: try await reader.patch(file: file, range: snapshot.range), as: UTF8.self)
        #expect(patch.contains(outside.path))
        #expect(!patch.contains("outside-secret-never-read"))
    }

    @Test func hostileRevisionAndInheritedHelpersCannotWrite() async throws {
        let f = try GitFixture(); defer { f.remove() }
        let repo = try await f.makeRepo("options")
        let output = f.url.appending(path: "sentinel")
        let git = try GitReadOnly(repository: repo, executable: f.git.executable, timeout: TestWait.limit)
        await #expect(throws: CompareError.self) { try await git.resolve("--output=" + output.path) }
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(!GitReadOnly.permits(["diff", "--output=" + output.path]))
    }
}
