@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// PLAN §10.2, after the move: a binary that still uses `…/clean-claude` (an older app or CLI) and the new app
/// exclude each other's cleanups through the link. Two processes; temp folders only.
@Suite("Settings folder move: an older binary afterwards")
@MainActor
struct SettingsFolderMoveCLITests {
    @Test func aCLIStillUsingTheOldFolderIsRefusedWhileTheAppCleansUp() async throws {
        let home = try TemporaryDirectory(prefix: "bonsai-move-cli")
        defer { home.remove() }
        let library = home.url.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        let old = library.appending(path: "clean-claude", directoryHint: .isDirectory)
        try SettingsStore(directory: old).save(Settings())
        let (environment, notice) = CleanEnvironment.launch(homeDirectory: home.url, variables: [:], tools: ToolPaths())
        #expect(notice == nil)
        #expect(environment.settingsDirectory.lastPathComponent == "Bonsai")
        let app = AppModel(environment: environment)

        // The CLI as an older binary has it: its settings folder is the old path, now the link.
        let root = home.url.appending(path: "empty-root", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let inherited = ProcessInfo.processInfo.environment.filter { key, _ in
            !EnvironmentName.allCases.contains { [$0.name, $0.oldName].contains(key) }
        }
        func prune() async throws -> ProcessResult {
            try await CLIBinary.run(
                ["prune", "--root", root.path, "--yes"],
                environment: [
                    "CLEAN_CLAUDE_SETTINGS_DIR": old.path,
                    "CLAUDE_CONFIG_DIR": home.url.appending(path: "claude").path,
                ],
                inheritedEnvironment: inherited
            )
        }

        let whileCleaning = try #require(await app.cleaningUp { try? await prune() })
        let refused = try #require(whileCleaning)
        #expect(!refused.succeeded)
        #expect(refused.stderr.contains(CleanupLock.busyMessage), "\(refused.stderr)")

        let afterwards = try await prune()
        #expect(afterwards.succeeded, "\(afterwards.stderr)")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: old.path) == "Bonsai", "no folder of its own")
    }
}
