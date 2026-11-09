@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// The details panel's "Unsaved changes" (P12b addition): every file `git status` lists, with a plain word for its
/// state, read-only, new with each scan; the Remove anyway list shows the same rows.
@Suite("Unsaved files")
@MainActor
struct UnsavedFilesTests {
    /// A sibling worktree with a modified, a deleted, a renamed, a staged new and an untracked file.
    private func world() async throws -> (GitFixture, URL, AppModel, WorktreesModel) {
        let fixture = try GitFixture()
        let repo = try await fixture.makeRepo("alpha")
        for name in ["a.txt", "b.txt", "c.txt"] { try fixture.write("\(name)\n", to: name, in: repo) }
        try await fixture.commitAll(in: repo, message: "Three files")
        try await fixture.run(["push", "--quiet", "origin", "main"], in: repo)
        let wt = try await fixture.addSiblingWorktree(to: repo, name: "home-redesign")
        try fixture.write("a, edited\n", to: "a.txt", in: wt)
        try FileManager.default.removeItem(at: wt.appending(path: "b.txt"))
        try await fixture.run(["mv", "c.txt", "d.txt"], in: wt)
        try fixture.write("staged\n", to: "f.txt", in: wt)
        try await fixture.run(["add", "f.txt"], in: wt)
        try fixture.write("draft\n", to: "notes/e.txt", in: wt)
        let app = makeApp(fixture)
        await app.refresh()
        return (fixture, wt, app, showingAll(WorktreesModel(app: app)))
    }

    /// `git status --porcelain=v1 -z --untracked-files=all`, read here without the app's parser: (letters, path, from).
    private func gitStatus(_ fixture: GitFixture, _ wt: URL) async throws -> [(String, String, String?)] {
        let data = try await fixture.git.git(["status", "--porcelain=v1", "-z", "--untracked-files=all"], in: wt)
        var fields = data.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }[...]
        var entries: [(String, String, String?)] = []
        while let field = fields.popFirst() {
            let code = String(field.prefix(2))
            let from = code.contains("R") ? fields.popFirst() : nil
            entries.append((code, String(field.dropFirst(3)), from))
        }
        return entries
    }

    @Test func theListIsExactlyWhatGitStatusSays() async throws {
        let (fixture, wt, app, model) = try await world()
        defer { fixture.remove() }
        let row = try #require(model.row(wt))
        let files = row.unsavedFiles
        let status = try await gitStatus(fixture, wt)

        #expect(files.map(\.path) == status.map(\.1), "every path, in git's order")
        let expected: [String: (word: String, detail: String?, gone: Bool)] = [
            "a.txt": ("Modified", nil, false), "b.txt": ("Deleted", nil, true), "d.txt": ("Renamed", "from c.txt", false),
            "f.txt": ("New", nil, false), "notes/e.txt": ("New", nil, false),
        ]
        #expect(Set(files.map(\.path)) == Set(expected.keys))
        for file in files {
            let want = try #require(expected[file.path])
            #expect(file.word == want.word && file.detail == want.detail && file.isGone == want.gone, "\(file)")
            #expect(file.fullPath == CanonicalPath.resolve(wt) + "/" + file.path, "inside the worktree")
        }
        #expect(row.chip.text == "5 unsaved changes")

        // Remove anyway's list shows the same rows.
        model.selection = [row.id]
        await model.beginRemoveAnyway()
        let confirmation = try #require(model.removeAnywayConfirmation)
        let section = try #require(confirmation.lossList.sections.first { $0.category == .uncommittedFiles })
        #expect(WorktreeFileRow.rows(for: section, in: confirmation.worktree.url) == files)
        model.dismissRemoveAnyway()

        // Read-only: looking changed nothing; and the list is new with the next scan.
        #expect(try await gitStatus(fixture, wt).map(\.1) == status.map(\.1))
        try await fixture.commitAll(in: wt, message: "Keep it all")
        await app.refresh()
        #expect(try #require(model.row(wt)).unsavedFiles.isEmpty)
    }

    @Test func openNeverRunsAnything() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "opening-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appending(path: "Tool.app/Contents"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appending(path: "docs"), withIntermediateDirectories: true)
        for name in ["notes.md", "deploy.command", "run.sh", "script"] {
            try Data("x\n".utf8).write(to: folder.appending(path: name))
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.appending(path: "script").path)
        try FileManager.default.createSymbolicLink(at: folder.appending(path: "link"), withDestinationURL: folder.appending(path: "notes.md"))

        #expect(FileOpening.way(for: folder.appending(path: "notes.md")) == .defaultApp)
        #expect(FileOpening.way(for: folder.appending(path: "docs", directoryHint: .isDirectory)) == .defaultApp)
        #expect(FileOpening.way(for: folder.appending(path: "deploy.command")) == .asText)
        #expect(FileOpening.way(for: folder.appending(path: "run.sh")) == .asText)
        #expect(FileOpening.way(for: folder.appending(path: "script")) == .asText)
        #expect(FileOpening.way(for: folder.appending(path: "Tool.app", directoryHint: .isDirectory)) == .finderOnly)
        #expect(FileOpening.way(for: folder.appending(path: "link")) == .finderOnly)
        #expect(FileOpening.way(for: folder.appending(path: "missing.txt")) == .finderOnly)
    }
}
