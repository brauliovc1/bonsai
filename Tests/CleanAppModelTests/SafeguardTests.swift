import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// Review items 7, 8 and 9: what Finder/Terminal, fixture-world and the Makefile are allowed to touch.
@Suite("Folder, fixture-world and Makefile safeguards")
struct SafeguardTests {
    /// 7: only a real folder is revealed or opened in Terminal (Terminal runs a file it is asked to open).
    @Test func onlyRealFoldersAreOpened() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let folder = directory.url.appending(path: "folder", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let script = directory.url.appending(path: "run.command")
        try Data("#!/bin/sh\necho hi\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let link = directory.url.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)

        #expect(FolderCheck.isRealDirectory(folder))
        #expect(!FolderCheck.isRealDirectory(script))
        #expect(!FolderCheck.isRealDirectory(link))
        #expect(!FolderCheck.isRealDirectory(directory.url.appending(path: "missing")))
    }

    /// 8: fixture-world refuses a folder it can't list instead of taking it for empty.
    @Test func fixtureWorldRefusesWhatItCanNotUse() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let locked = directory.url.appending(path: "locked", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        #expect(DemoWorld.problem(withTarget: locked)?.contains("can't be listed") == true)
        #expect(DemoWorld.problem(withTarget: directory.url.appending(path: "new")) == nil, "missing: created")
        let empty = directory.url.appending(path: "empty", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(DemoWorld.problem(withTarget: empty) == nil)
        try Data().write(to: empty.appending(path: "x"))
        #expect(DemoWorld.problem(withTarget: empty)?.contains("not empty") == true)
        #expect(DemoWorld.problem(withTarget: empty.appending(path: "x"))?.contains("not a folder") == true)
        let home = FileManager.default.homeDirectoryForCurrentUser.appending(path: "demo-world")
        #expect(DemoWorld.problem(withTarget: home)?.contains("is not inside") == true)
    }

    /// 9: the Makefile refuses destinations that would make rm -rf, rm -f, cp or ln hit something else, before it
    /// runs anything: git and swift stand-ins first on PATH record every call, and a refusal makes none. Dry runs
    /// only, and none of them runs swift.
    @Test func makefileRefusesUnsafeDestinations() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let tools = try TemporaryDirectory()
        defer { tools.remove() }
        let calls = try writeStandIns(in: tools.url)
        let refusals = [
            ("APP_NAME=Utilities/Terminal", "APP_NAME must not contain \"/\""),
            ("APP_NAME=", "APP_NAME must not be empty"),
            ("OLD_CLI=../bin/bonsai", "OLD_CLI must not contain \"/\""),
            ("OLD_CLI=", "OLD_CLI must not be empty"),
            ("INSTALL_DIR=relative/dir", "INSTALL_DIR must be an absolute path"),
            ("INSTALL_DIR=", "INSTALL_DIR must be an absolute path"),
            ("BIN_DIR=", "BIN_DIR must be an absolute path"),
        ]
        for (argument, message) in refusals {
            let result = try await make(["-n", "-C", root.path, "install", argument], tools: tools.url)
            #expect(!result.succeeded, "\(argument)")
            #expect(result.stderr.contains(message), "\(argument): \(result.stderr)")
            #expect(recorded(calls).isEmpty, "\(argument): ran \(recorded(calls)) before refusing")
        }

        let elsewhere = try TemporaryDirectory()
        defer { elsewhere.remove() }
        let clean = try await make(
            ["-n", "-f", root.appending(path: "Makefile").path, "clean"], tools: tools.url, in: elsewhere.url
        )
        #expect(clean.stdoutString.contains("rm -rf \"\(CanonicalPath.resolve(root))/build\""), "\(clean.stdoutString)")
        #expect(!clean.stdoutString.contains("rm -rf \"build\""))

        let destination = elsewhere.url.path
        let install = try await make([
            "-n", "-C", root.path, "install", "INSTALL_DIR=\(destination)/Applications", "BIN_DIR=\(destination)/bin",
        ], tools: tools.url)
        #expect(install.succeeded, "\(install.stderr)")
        #expect(recorded(calls).contains { $0.hasPrefix("git ") }, "the stand-ins are the ones make runs")
        #expect(!recorded(calls).contains { $0.hasPrefix("swift") }, "a dry run builds nothing: \(recorded(calls))")
        let lines = install.stdoutString.split(separator: "\n").map(String.init)
        let removeCLI = try #require(lines.firstIndex(of: "rm -f \"\(destination)/bin/bonsai\""))
        let copyCLI = try #require(lines.firstIndex { $0.hasPrefix("cp ") && $0.hasSuffix("\"\(destination)/bin/bonsai\"") })
        #expect(removeCLI < copyCLI, "a symlinked target is replaced, not written through")
        // The old name stays as a link to the new one, so old scripts keep working (PLAN §10.2).
        let removeOld = try #require(lines.firstIndex(of: "rm -f \"\(destination)/bin/clean-claude\""))
        let linkOld = try #require(lines.firstIndex(of: "ln -s \"bonsai\" \"\(destination)/bin/clean-claude\""))
        #expect(copyCLI < removeOld && removeOld < linkOld)
        #expect(install.stdoutString.contains("is running from"), "the running-app check comes before anything is replaced")
    }

    /// `/usr/bin/make` with `tools` first on PATH. It may take as long as the machine needs (`make` and `git` are
    /// xcrun shims, slow on a cold runner), and says so when it doesn't finish.
    private func make(
        _ arguments: [String], tools: URL, in directory: URL? = nil, sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> ProcessResult {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        let result = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/make"), arguments: arguments, directory: directory,
            environmentAdditions: ["PATH": "\(tools.path):\(path)"], timeout: TestWait.limit
        )
        #expect(!result.timedOut, "make \(arguments.joined(separator: " ")) didn't finish within \(TestWait.limit)",
                sourceLocation: sourceLocation)
        return result
    }

    /// `git` and `swift` in `tools` that add a line to the returned file for each call; git then runs the real one,
    /// swift fails.
    private func writeStandIns(in tools: URL) throws -> URL {
        let calls = tools.appending(path: "calls")
        for (name, then) in [("git", "exec /usr/bin/git \"$@\""), ("swift", "exit 1")] {
            let script = tools.appending(path: name)
            try Data("#!/bin/sh\necho \"\(name) $*\" >> '\(calls.path)'\n\(then)\n".utf8).write(to: script)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        }
        return calls
    }

    private func recorded(_ calls: URL) -> [String] {
        ((try? String(contentsOf: calls, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }
}
