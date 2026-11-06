@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Claude usage model")
@MainActor
struct ClaudeUsageModelTests {
    @Test func totalsAndTablesComeFromTheReport() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        try home.addFile(".claude/projects/-Users-me-app/a.jsonl", kibibytes: 40)
        try home.addFile(".claude/projects/-Users-me-other/b.jsonl", kibibytes: 12)
        try home.addFile(".claude/file-history/f/v1", kibibytes: 8)
        try home.addFile(".local/share/claude/versions/2.1.9", kibibytes: 16)
        try home.addFile(".local/share/claude/versions/2.1.10", kibibytes: 16)
        try home.addFile("Library/Application Support/Claude/vm_bundles/big.img", kibibytes: 100)
        try home.addFile("Library/Application Support/Claude/Cache/c", kibibytes: 4)
        let model = ClaudeUsageModel(app: AppModel(environment: home.environment()))
        #expect(model.report == nil)

        await model.refresh()

        #expect(model.summaryLines.map(\.title) == [
            "Transcripts", "File history", "Claude Code versions", "Claude desktop app data",
        ])
        #expect(model.summaryLines[0].detail == "2 project folders")
        #expect(model.summaryLines[0].bytes == Int64(52 * 1024))
        #expect(model.summaryLines[1].bytes == Int64(8 * 1024))
        #expect(model.summaryLines[2].detail == "2 installed")
        #expect(model.summaryLines[3].bytes == Int64(104 * 1024))
        #expect(model.totalText == DisplayText.bytes(Int64((52 + 8 + 32 + 104) * 1024)))
        #expect(model.transcriptRows.map(\.title) == ["-Users-me-app", "-Users-me-other"], "largest first, raw names")
        #expect(model.transcriptRows.allSatisfy { !$0.isDecoded && $0.note == "path not recognized" })
        #expect(model.versionNames == ["2.1.9", "2.1.10"])
        #expect(model.desktopRows.first?.title == "vm_bundles")
        #expect(model.lastScanAt != nil)
        #expect(ClaudeUsageModel.note
            == "Clean these from Claude > Settings > This computer > Storage. Clean Claude never deletes Claude's data.")
    }

    @Test func aTranscriptFolderWhoseProjectIsGoneGetsTheFolderGoneBadge() async throws {
        let demo = try await DemoWorld.build()
        defer { demo.remove() }
        let app = AppModel(environment: demo.fixture.environment(scanRoots: [demo.folder]), git: demo.fixture.git)
        await app.refresh()
        let claudeProjects = app.environment.claudeConfigDirectory.appending(path: "projects", directoryHint: .isDirectory)
        func transcript(for folder: URL, kibibytes: Int) throws {
            let name = ClaudeProjectFolderName.encode(folder.path)
            let file = claudeProjects.appending(path: "\(name)/session.jsonl")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(count: kibibytes * 1024).write(to: file)
        }
        // Claude names the folder after the path git prints for the worktree (symlinks resolved).
        func registered(_ name: String) throws -> URL {
            let worktree = try #require(app.assessments.first { $0.worktree.url.lastPathComponent == name }?.worktree)
            return worktree.url
        }
        try transcript(for: try registered("beacon-gone"), kibibytes: 40)  // registered, folder deleted
        try transcript(for: try registered("atlas-archive"), kibibytes: 20)  // still there
        try transcript(for: URL(fileURLWithPath: "/Users/clean-claude-no-such-user/unknown"), kibibytes: 8)
        let model = ClaudeUsageModel(app: app)

        await model.refresh()

        let rows = model.transcriptRows
        #expect(rows.count == 3)
        let gone = try #require(rows.first { $0.title.hasSuffix("beacon-gone") })
        #expect(gone.isDecoded && gone.folderGone)
        let present = try #require(rows.first { $0.title.hasSuffix("atlas-archive") })
        #expect(present.isDecoded && !present.folderGone)
        let unknown = try #require(rows.first { !$0.isDecoded })
        #expect(!unknown.folderGone, "no badge when the project is not known")
        #expect(unknown.note == "path not recognized")
    }

    @Test func refreshingChangesNothingOnDisk() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        try home.addFile(".claude/projects/-Users-me-app/a.jsonl", kibibytes: 8)
        try home.addFile("Library/Application Support/Claude/vm_bundles/big.img", kibibytes: 8)
        func snapshot() -> [String: Date?] {
            var result: [String: Date?] = [:]
            let enumerator = FileManager.default.enumerator(atPath: home.url.path)
            while let path = enumerator?.nextObject() as? String {
                let attributes = try? FileManager.default.attributesOfItem(atPath: home.url.appending(path: path).path)
                result[path] = attributes?[.modificationDate] as? Date
            }
            return result
        }
        let before = snapshot()
        let model = ClaudeUsageModel(app: AppModel(environment: home.environment()))
        await model.refresh()
        await model.refresh()
        #expect(snapshot() == before)
    }

    // MARK: - No way to delete

    private static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Calls that change files or start programs: none may appear in the screen's model, rows or view.
    private static let forbiddenCalls = [
        "removeItem", "trashItem", "moveItem", "copyItem", "replaceItem", "linkItem", "createFile",
        "createDirectory", "createSymbolicLink", "setAttributes", "write(", "truncate", "FileHandle(forWriting",
        "FileHandle(forUpdating", "Process(", "ProcessRunner", "CommandRunner", "NSWorkspace",
        "RemovalLog", "Remover", "Cleaner", "cleaningUp", "cleanupFinished",
    ]

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: Self.repo.appending(path: relative), encoding: .utf8)
    }

    @Test func theModelAndItsViewCannotChangeAnything() throws {
        let files = [
            "Sources/CleanAppModel/ClaudeUsageModel.swift",
            "Sources/CleanAppModel/ClaudeUsageRows.swift",
            "Sources/CleanClaudeApp/ClaudeUsageView.swift",
        ]
        for file in files {
            let text = try source(file)
            #expect(text.count > 500, "\(file) was found")
            let found = Self.forbiddenCalls.filter { text.contains($0) }
            #expect(found.isEmpty, "\(file): \(found)")
        }
    }

    @Test func theViewHasNoDeleteOrRemoveControlAndOnlyOneButton() throws {
        let view = try source("Sources/CleanClaudeApp/ClaudeUsageView.swift")
        for word in ["delete", "remove", "trash", "clean up", "destructive"] {
            #expect(!view.lowercased().contains(word), "the Claude usage view mentions \(word)")
        }
        #expect(view.components(separatedBy: "Button").count - 1 == 1, "only Refresh")
        #expect(view.contains("model.refresh()"))
    }

    @Test func theModelExposesOnlyRefresh() throws {
        let text = try source("Sources/CleanAppModel/ClaudeUsageModel.swift")
        let functions = text.split(separator: "\n").compactMap { line -> String? in
            guard let range = line.range(of: "func ") else { return nil }
            return String(line[range.upperBound...].prefix { $0 != "(" && $0 != "<" })
        }
        #expect(functions == ["refresh"], "\(functions)")
    }
}
