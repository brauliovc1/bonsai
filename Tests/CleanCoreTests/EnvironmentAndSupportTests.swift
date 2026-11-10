import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("CleanEnvironment, sizes and paths")
struct EnvironmentAndSupportTests {
    private let home = URL(fileURLWithPath: "/Users/tester")

    @Test func defaultsWithoutVariables() {
        let environment = CleanEnvironment.make(homeDirectory: home, variables: [:], tools: ToolPaths())
        #expect(environment.claudeConfigDirectory.path == "/Users/tester/.claude")
        #expect(environment.claudeDesktopDirectory.path == "/Users/tester/Library/Application Support/Claude")
        #expect(environment.cursorWorktreesDirectory.path == "/Users/tester/.cursor/worktrees")
        #expect(environment.settingsDirectory.path == "/Users/tester/Library/Application Support/Bonsai")
        #expect(environment.scanRootsOverride == nil)
    }

    @Test func variablesOverrideDefaults() {
        let environment = CleanEnvironment.make(
            homeDirectory: home,
            variables: [
                "CLAUDE_CONFIG_DIR": "/opt/claude-config",
                "BONSAI_SETTINGS_DIR": "~/tmp/settings",
                "BONSAI_SCAN_ROOTS": "/a:~/b::/c/../d",
            ],
            tools: ToolPaths()
        )
        #expect(environment.claudeConfigDirectory.path == "/opt/claude-config")
        #expect(environment.settingsDirectory.path == "/Users/tester/tmp/settings")
        #expect(environment.scanRootsOverride?.map(\.path) == ["/a", "/Users/tester/b", "/d"])
    }

    @Test func emptyVariablesAreUnset() {
        let environment = CleanEnvironment.make(
            homeDirectory: home,
            variables: ["CLAUDE_CONFIG_DIR": "", "BONSAI_SCAN_ROOTS": "::"],
            tools: ToolPaths()
        )
        #expect(environment.claudeConfigDirectory.path == "/Users/tester/.claude")
        #expect(environment.scanRootsOverride == nil)
    }

    /// The app and the CLI run git and lsof with these; only tests give them more time.
    @Test func toolTimeoutsKeepTheShippedDefaults() {
        let git = URL(fileURLWithPath: "/usr/bin/git")
        let tools = ToolPaths(git: git, lsof: URL(fileURLWithPath: "/usr/sbin/lsof"))
        let environment = CleanEnvironment.make(homeDirectory: home, variables: [:], tools: tools)
        #expect(environment.timeouts == ToolTimeouts(git: .seconds(60), gitVersion: .seconds(10), lsof: .seconds(30)))
        #expect(WorktreeAssessor.git(for: environment)?.timeout == .seconds(60))
        let assessor = WorktreeAssessor(git: Git(executable: git), settings: Settings(), environment: environment)
        #expect(assessor.lsofTimeout == .seconds(30))
    }

    @Test func fixtureEnvironmentStaysInsideTheFixture() throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let environment = fixture.environment()
        for directory in [environment.homeDirectory, environment.claudeConfigDirectory,
                          environment.claudeDesktopDirectory, environment.cursorWorktreesDirectory,
                          environment.settingsDirectory] {
            #expect(CanonicalPath.isInside(directory, directory: fixture.url), "\(directory.path)")
        }
    }

    @Test func canonicalPathSeesThroughSymlinks() {
        #expect(CanonicalPath.resolve("/tmp") == "/private/tmp")
        #expect(CanonicalPath.resolve("/tmp/cc-missing/a/../b/") == "/private/tmp/cc-missing/b")
        #expect(CanonicalPath.same(URL(fileURLWithPath: "/tmp/x"), URL(fileURLWithPath: "/private/tmp/x")))
        #expect(CanonicalPath.relativePath(
            of: URL(fileURLWithPath: "/private/tmp/r/a/b"),
            to: URL(fileURLWithPath: "/tmp/r")
        ) == "a/b")
        #expect(CanonicalPath.relativePath(of: URL(fileURLWithPath: "/tmp/r"), to: URL(fileURLWithPath: "/tmp/r")) == ".")
        #expect(CanonicalPath.relativePath(of: URL(fileURLWithPath: "/tmp/rx"), to: URL(fileURLWithPath: "/tmp/r")) == nil)
        #expect(!CanonicalPath.isInside(URL(fileURLWithPath: "/tmp/r"), directory: URL(fileURLWithPath: "/tmp/r")))
    }

    @Test func duOutputParsing() {
        #expect(DirectorySizer.parseKilobytes(Data("1234\t/some path\n".utf8)) == 1234)
        #expect(DirectorySizer.parseKilobytes(Data("0\t/x\n".utf8)) == 0)
        #expect(DirectorySizer.parseKilobytes(Data("du: /x: Permission denied\n".utf8)) == nil)
        #expect(DirectorySizer.parseKilobytes(Data()) == nil)
    }

    @Test func directorySizes() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let folder = temp.url.appending(path: "with space")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(count: 200 * 1024).write(to: folder.appending(path: "blob"))
        let missing = temp.url.appending(path: "missing")

        let sizer = DirectorySizer(du: URL(fileURLWithPath: "/usr/bin/du"))
        let bytes = try #require(try await sizer.size(of: folder))
        #expect(bytes >= 200 * 1024)
        #expect(bytes % 1024 == 0)
        #expect(try await sizer.size(of: missing) == nil)

        let batch = await sizer.sizes(of: [folder, missing])
        #expect(batch.sizes == [folder.path: bytes])
        #expect(batch.issues.isEmpty)
    }

    @Test func unreadableSubfolderStillSized() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let locked = temp.url.appending(path: "locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data(count: 64 * 1024).write(to: temp.url.appending(path: "file"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let bytes = try await DirectorySizer(du: URL(fileURLWithPath: "/usr/bin/du")).size(of: temp.url)
        #expect((bytes ?? 0) >= 64 * 1024)
    }

    @Test func byteFormatting() {
        #expect(ByteFormatting.string(0) == "0.0 KB")
        #expect(ByteFormatting.string(1536) == "1.5 KB")
        #expect(ByteFormatting.string(5 * 1024 * 1024) == "5.0 MB")
        #expect(ByteFormatting.string(Int64(2.5 * 1024 * 1024 * 1024)) == "2.5 GB")
        #expect(ByteFormatting.string(1023 * 1024) == "1023.0 KB")
        #expect(ByteFormatting.string(3 * 1024 * 1024 * 1024 * 1024) == "3.0 TB")
    }

    @Test func boundedConcurrencyKeepsOrderAndLimit() async {
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var current = 0
            private(set) var peak = 0
            func enter() { lock.withLock { current += 1; peak = max(peak, current) } }
            func leave() { lock.withLock { current -= 1 } }
        }
        let counter = Counter()
        // The first stays until a second runs alongside it, however late that one starts; a map that runs one at a
        // time holds them up only until `end`, once for all of them.
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: TestWait.limit)
        let output = await BoundedConcurrency.map(Array(0..<20), limit: 4) { value in
            counter.enter()
            while counter.peak < 2, clock.now < end {
                try? await Task.sleep(for: .milliseconds(1))
            }
            counter.leave()
            return value * 2
        }
        #expect(output == (0..<20).map { $0 * 2 })
        #expect(counter.peak <= 4)
        #expect(counter.peak >= 2)
    }
}
