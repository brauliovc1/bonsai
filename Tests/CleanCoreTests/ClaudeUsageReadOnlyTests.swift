import Foundation
import Testing

/// The ClaudeUsage folder has no way to change anything on disk. If a delete, trash or write call is ever
/// added there, this fails.
@Suite("ClaudeUsage is read-only")
struct ClaudeUsageReadOnlyTests {
    static let forbidden = ["removeItem", "trashItem", "write(", "createFile"]

    static func violations(in source: String) -> [String] {
        forbidden.filter { source.contains($0) }
    }

    /// `<repo>/Sources/CleanCore/ClaudeUsage`, found from this file's own path.
    static var sourceFolder: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // CleanCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo
            .appending(path: "Sources/CleanCore/ClaudeUsage", directoryHint: .isDirectory)
    }

    @Test func theCheckItselfCatchesEachForbiddenCall() {
        #expect(Self.violations(in: "try FileManager.default.removeItem(at: url)") == ["removeItem"])
        #expect(Self.violations(in: "try FileManager.default.trashItem(at: url, resultingItemURL: nil)") == ["trashItem"])
        #expect(Self.violations(in: "try data.write(to: url)") == ["write("])
        #expect(Self.violations(in: "FileManager.default.createFile(atPath: p, contents: nil)") == ["createFile"])
        #expect(Self.violations(in: "let sizes = try await sizer.allocatedSizes(ofItems: items)").isEmpty)
    }

    @Test func noClaudeUsageSourceFileContainsAForbiddenCall() throws {
        let files = try FileManager.default
            .contentsOfDirectory(at: Self.sourceFolder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        // Guards against the test passing because it looked in the wrong place.
        #expect(files.count >= 3, "found \(files.count) source files in \(Self.sourceFolder.path)")

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(Self.violations(in: source).isEmpty, "\(file.lastPathComponent): \(Self.violations(in: source))")
        }
    }
}
