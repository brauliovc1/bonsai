@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Command support")
struct CommandSupportTests {
    @Test func displayQuotesOnlyWhatNeedsIt() {
        #expect(CommandLineDisplay.string(executable: "/usr/bin/xcrun", arguments: ["simctl", "delete", "unavailable"])
            == "/usr/bin/xcrun simctl delete unavailable")
        #expect(CommandLineDisplay.string(executable: "/opt/homebrew/bin/docker", arguments: ["system", "prune", "-f"])
            == "/opt/homebrew/bin/docker system prune -f")
        #expect(CommandLineDisplay.string(executable: "/Applications/My Tools/docker", arguments: ["--format", "{{json .}}", "it's", ""])
            == "'/Applications/My Tools/docker' --format '{{json .}}' 'it'\\''s' ''")
    }

    @Test func liveRunnerStartsARealProcessWithAnArgumentArray() async throws {
        // /bin/echo only prints its arguments; nothing is changed.
        let result = try await CommandRunner.live.run(
            URL(fileURLWithPath: "/bin/echo"),
            ["a b", "$HOME"],
            timeout: .seconds(10)
        )
        #expect(result.succeeded)
        #expect(result.stdoutString == "a b $HOME\n")
    }

    @Test func liveRunnerThrowsForAMissingExecutable() async {
        await #expect(throws: (any Error).self) {
            _ = try await CommandRunner.live.run(URL(fileURLWithPath: "/nonexistent/tool"), [], timeout: .seconds(5))
        }
    }

    @Test func freeSpaceProbeReadsTheVolumeOfAFolder() {
        let probe = FreeSpaceProbe.volume(containing: FileManager.default.temporaryDirectory)
        #expect((probe.availableBytes() ?? 0) > 0)
    }

    @Test func scriptedFreeSpaceRepeatsItsLastValue() {
        let probe = ScriptedFreeSpace([1, 2]).probe
        #expect([probe.availableBytes(), probe.availableBytes(), probe.availableBytes()] == [1, 2, 2])
    }
}

@Suite("DirectorySizer items")
struct DirectorySizerItemsTests {
    private let sizer = DirectorySizer(du: URL(fileURLWithPath: "/usr/bin/du"))

    @Test func measuresFilesAndFoldersAndSkipsMissingOnes() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let file = try home.addFile("one.bin", kibibytes: 12)
        let folder = try home.addFolder("dir")
        try home.addFile("dir/a.bin", kibibytes: 8)
        try home.addFile("dir/sub/b.bin", kibibytes: 4)
        let missing = home.url.appending(path: "missing")

        #expect(try await sizer.allocatedSize(ofItem: file) == 12 * 1024)
        #expect(try await sizer.allocatedSize(ofItem: folder) == 12 * 1024)
        #expect(try await sizer.allocatedSize(ofItem: missing) == nil)

        let many = await sizer.allocatedSizes(ofItems: [file, folder, missing])
        #expect(many.sizes == [file.path: 12 * 1024, folder.path: 12 * 1024])
        #expect(many.issues.isEmpty)
    }

    @Test func symlinksAreMeasuredAsTheirTargetsAndBrokenOnesAreMissing() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let file = try home.addFile("real/one.bin", kibibytes: 12)
        let folder = try home.addFolder("real/dir")
        try home.addFile("real/dir/a.bin", kibibytes: 8)
        let fileLink = home.url.appending(path: "file-link")
        let folderLink = home.url.appending(path: "folder-link")
        let brokenLink = home.url.appending(path: "broken-link")
        try FileManager.default.createSymbolicLink(at: fileLink, withDestinationURL: file)
        try FileManager.default.createSymbolicLink(at: folderLink, withDestinationURL: folder)
        try FileManager.default.createSymbolicLink(at: brokenLink, withDestinationURL: home.url.appending(path: "nowhere"))

        #expect(try await sizer.allocatedSize(ofItem: fileLink) == Int64(12 * 1024))
        #expect(try await sizer.allocatedSize(ofItem: folderLink) == Int64(8 * 1024))
        #expect(try await sizer.allocatedSize(ofItem: brokenLink) == nil)

        let many = await sizer.allocatedSizes(ofItems: [fileLink, folderLink, brokenLink])
        #expect(many.sizes == [fileLink.path: Int64(12 * 1024), folderLink.path: Int64(8 * 1024)], "keyed by the path asked for")
        #expect(many.issues.isEmpty)
    }

    @Test func aSparseFileCountsForWhatItAllocates() async throws {
        let home = try FakeHome()
        defer { home.remove() }
        let sparse = home.url.appending(path: "sparse.raw")
        #expect(FileManager.default.createFile(atPath: sparse.path, contents: Data(count: 4096)))
        let handle = try FileHandle(forWritingTo: sparse)
        try handle.truncate(atOffset: 1 << 30)  // 1 GiB apparent size, almost nothing allocated
        try handle.close()

        let bytes = try #require(try await sizer.allocatedSize(ofItem: sparse))
        #expect(bytes < 1 << 20, "du counts allocated blocks, not the apparent size: \(bytes)")
    }
}
