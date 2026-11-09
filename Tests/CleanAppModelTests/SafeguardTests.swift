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

    /// 9: the Makefile refuses destinations that would make rm -rf or cp hit something else. Dry runs only.
    @Test func makefileRefusesUnsafeDestinations() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let make = URL(fileURLWithPath: "/usr/bin/make")
        let refusals = [
            ("APP_NAME=Utilities/Terminal", "APP_NAME must not contain \"/\""),
            ("APP_NAME=", "APP_NAME must not be empty"),
            ("INSTALL_DIR=relative/dir", "INSTALL_DIR must be an absolute path"),
            ("INSTALL_DIR=", "INSTALL_DIR must be an absolute path"),
            ("BIN_DIR=", "BIN_DIR must be an absolute path"),
        ]
        for (argument, message) in refusals {
            let result = try await ProcessRunner.run(executable: make, arguments: ["-n", "-C", root.path, "install", argument])
            #expect(!result.succeeded, "\(argument)")
            #expect(result.stderr.contains(message), "\(argument): \(result.stderr)")
        }

        let elsewhere = try TemporaryDirectory()
        defer { elsewhere.remove() }
        let clean = try await ProcessRunner.run(
            executable: make,
            arguments: ["-n", "-f", root.appending(path: "Makefile").path, "clean"],
            directory: elsewhere.url
        )
        #expect(clean.stdoutString.contains("rm -rf \"\(CanonicalPath.resolve(root))/build\""), "\(clean.stdoutString)")
        #expect(!clean.stdoutString.contains("rm -rf \"build\""))

        let destination = elsewhere.url.path
        let install = try await ProcessRunner.run(executable: make, arguments: [
            "-n", "-C", root.path, "install", "INSTALL_DIR=\(destination)/Applications", "BIN_DIR=\(destination)/bin",
        ])
        #expect(install.succeeded, "\(install.stderr)")
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
}
