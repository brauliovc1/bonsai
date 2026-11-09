import Foundation

/// Everything CleanCore needs to know about the machine it runs on.
///
/// This is the only place that reads `ProcessInfo` and the real home directory (apart from
/// `ProcessRunner`, which passes the inherited environment on to child processes). Every other type
/// takes an environment, so tests can point all of it at a temp folder.
public struct CleanEnvironment: Sendable {
    public var homeDirectory: URL
    /// `$CLAUDE_CONFIG_DIR`, else `~/.claude`. Read-only for Bonsai.
    public var claudeConfigDirectory: URL
    /// `~/Library/Application Support/Claude`. Read-only for Bonsai.
    public var claudeDesktopDirectory: URL
    /// `~/.cursor/worktrees`.
    public var cursorWorktreesDirectory: URL
    /// `$BONSAI_SETTINGS_DIR`, else `~/Library/Application Support/Bonsai` (`launch` may pick the old
    /// `clean-claude` folder for one run; see `SettingsFolderMove`).
    public var settingsDirectory: URL
    /// `$BONSAI_SCAN_ROOTS` split on `:`; nil when unset or empty. Both read through `EnvironmentName`.
    public var scanRootsOverride: [URL]?
    public var now: @Sendable () -> Date
    public var tools: ToolPaths

    public init(
        homeDirectory: URL,
        claudeConfigDirectory: URL,
        claudeDesktopDirectory: URL,
        cursorWorktreesDirectory: URL,
        settingsDirectory: URL,
        scanRootsOverride: [URL]? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        tools: ToolPaths
    ) {
        self.homeDirectory = homeDirectory
        self.claudeConfigDirectory = claudeConfigDirectory
        self.claudeDesktopDirectory = claudeDesktopDirectory
        self.cursorWorktreesDirectory = cursorWorktreesDirectory
        self.settingsDirectory = settingsDirectory
        self.scanRootsOverride = scanRootsOverride
        self.now = now
        self.tools = tools
    }

    /// The environment of the running process: real home, real environment variables, resolved tools.
    public static func live() -> CleanEnvironment {
        make(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            variables: ProcessInfo.processInfo.environment,
            tools: .resolve()
        )
    }

    /// Builds an environment from a home folder and a set of environment variables.
    public static func make(
        homeDirectory: URL,
        variables: [String: String],
        tools: ToolPaths,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> CleanEnvironment {
        let home = homeDirectory.standardized
        let library = home.appending(path: "Library/Application Support", directoryHint: .isDirectory)

        func directory(_ value: String?) -> URL? {
            guard let value, !value.isEmpty else { return nil }
            return expand(value, home: home)
        }

        let scanRoots = EnvironmentName.scanRoots.value(in: variables)?
            .split(separator: ":", omittingEmptySubsequences: true)
            .map { expand(String($0), home: home) }

        return CleanEnvironment(
            homeDirectory: home,
            claudeConfigDirectory: directory(variables["CLAUDE_CONFIG_DIR"])
                ?? home.appending(path: ".claude", directoryHint: .isDirectory),
            claudeDesktopDirectory: library.appending(path: "Claude", directoryHint: .isDirectory),
            cursorWorktreesDirectory: home.appending(path: ".cursor/worktrees", directoryHint: .isDirectory),
            settingsDirectory: directory(EnvironmentName.settingsDirectory.value(in: variables))
                ?? library.appending(path: SettingsFolderMove.newName, directoryHint: .isDirectory),
            scanRootsOverride: (scanRoots?.isEmpty ?? true) ? nil : scanRoots,
            now: now,
            tools: tools
        )
    }

    /// The live environment at launch (the app and the CLI, once per process). When no settings folder is named
    /// in the environment, the old `clean-claude` folder is first moved to `Bonsai` (PLAN §10.2), and the folder
    /// the move says is used. `notice` is what to tell the person, once.
    public static func launch() -> (environment: CleanEnvironment, notice: String?) {
        launch(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            variables: ProcessInfo.processInfo.environment,
            tools: .resolve()
        )
    }

    /// `launch()` for a given home folder and environment variables (tests use a temp home).
    public static func launch(
        homeDirectory: URL,
        variables: [String: String],
        tools: ToolPaths,
        lockTimeout: Duration = SettingsFolderMove.lockTimeout
    ) -> (environment: CleanEnvironment, notice: String?) {
        var environment = make(homeDirectory: homeDirectory, variables: variables, tools: tools)
        guard EnvironmentName.settingsDirectory.value(in: variables) == nil else { return (environment, nil) }
        let library = environment.settingsDirectory.deletingLastPathComponent()
        let move = SettingsFolderMove.run(in: library, lockTimeout: lockTimeout)
        environment.settingsDirectory = move.folder
        return (environment, move.notice)
    }

    /// Expands a leading `~` against `home` and makes the path absolute and lexically standardized.
    public static func expand(_ path: String, home: URL) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") {
            return home.appending(path: String(path.dropFirst(2))).standardized
        }
        return URL(fileURLWithPath: path).standardized
    }
}
