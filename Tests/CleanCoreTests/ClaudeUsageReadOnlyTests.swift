import Foundation
import Testing

/// The ClaudeUsage folder has no way to change anything on disk, and starts no process of its own (sizes
/// come from `DirectorySizer`, which only runs `du`). If a delete, move, write or process call is ever
/// added there, or to the sizing extension it uses, this fails.
@Suite("ClaudeUsage is read-only")
struct ClaudeUsageReadOnlyTests {
    /// Calls that change files. Checked in the ClaudeUsage folder and in `DirectorySizer+Items.swift`.
    static let mutatingCalls = [
        "removeItem", "trashItem", "moveItem", "copyItem", "replaceItem", "linkItem",
        "createFile", "createDirectory", "createSymbolicLink", "setAttributes",
        "write(", "truncate", "FileHandle(forWriting", "FileHandle(forUpdating",
    ]
    /// Ways to start another program. Checked in the ClaudeUsage folder only.
    static let processCalls = ["Process(", "ProcessRunner", "CommandRunner"]

    static func violations(in source: String, forbidden: [String]) -> [String] {
        forbidden.filter { source.contains($0) }
    }

    /// `<repo>/Sources/CleanCore`, found from this file's own path.
    static var coreFolder: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // CleanCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo
            .appending(path: "Sources/CleanCore", directoryHint: .isDirectory)
    }

    /// Every `.swift` file under `folder`, subfolders included.
    static func swiftFiles(under folder: URL) -> [URL] {
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        return (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
    }

    @Test func theCheckItselfCatchesEachForbiddenCall() {
        let all = Self.mutatingCalls + Self.processCalls
        for call in all {
            // "removeItem" also contains "moveItem", so a sample can match more than one pattern.
            #expect(Self.violations(in: "let x = thing.\(call)at: url)", forbidden: all).contains(call), "missed \(call)")
        }
        #expect(Self.violations(in: "let sizes = try await sizer.allocatedSizes(ofItems: items)", forbidden: all).isEmpty)
    }

    @Test func claudeUsageSourcesCannotChangeFilesOrStartProcesses() throws {
        let folder = Self.coreFolder.appending(path: "ClaudeUsage", directoryHint: .isDirectory)
        let files = Self.swiftFiles(under: folder)
        // Guards against the test passing because it looked in the wrong place.
        let names = Set(files.map(\.lastPathComponent))
        #expect(names.isSuperset(of: ["ClaudeUsageScanner.swift", "ClaudeUsageReport.swift", "ClaudeProjectFolderName.swift"]),
                "found \(names.sorted()) in \(folder.path)")

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let found = Self.violations(in: source, forbidden: Self.mutatingCalls + Self.processCalls)
            #expect(found.isEmpty, "\(file.lastPathComponent): \(found)")
        }
    }

    @Test func theSizingExtensionClaudeUsageCallsCannotChangeFiles() throws {
        let file = Self.coreFolder.appending(path: "Sizing/DirectorySizer+Items.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        #expect(source.contains("allocatedSize"), "the extension moved or was renamed")
        let found = Self.violations(in: source, forbidden: Self.mutatingCalls)
        #expect(found.isEmpty, "\(found)")
    }
}
