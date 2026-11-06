import Foundation

/// Everything CleanCore needs to know about the machine it runs on.
///
/// This is the only place that reads `ProcessInfo` and the real home directory (apart from
/// `ProcessRunner`, which passes the inherited environment on to child processes). Every other type
/// takes an environment, so tests can point all of it at a temp folder.
public struct CleanEnvironment: Sendable {
    public var homeDirectory: URL
    /// `$CLAUDE_CONFIG_DIR`, else `~/.claude`. Read-only for clean-claude.
    public var claudeConfigDirectory: URL
    /// `~/Library/Application Support/Claude`. Read-only for clean-claude.
    public var claudeDesktopDirectory: URL
    /// `~/.cursor/worktrees`.
    public var cursorWorktreesDirectory: URL
    /// `$CLEAN_CLAUDE_SETTINGS_DIR`, else `~/Library/Application Support/clean-claude`.
    public var settingsDirectory: URL
    /// `$CLEAN_CLAUDE_SCAN_ROOTS` split on `:`; nil when unset or empty.
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

        func directory(_ variable: String) -> URL? {
            guard let value = variables[variable], !value.isEmpty else { return nil }
            return expand(value, home: home)
        }

        let scanRoots = variables["CLEAN_CLAUDE_SCAN_ROOTS"]?
            .split(separator: ":", omittingEmptySubsequences: true)
            .map { expand(String($0), home: home) }

        return CleanEnvironment(
            homeDirectory: home,
            claudeConfigDirectory: directory("CLAUDE_CONFIG_DIR")
                ?? home.appending(path: ".claude", directoryHint: .isDirectory),
            claudeDesktopDirectory: library.appending(path: "Claude", directoryHint: .isDirectory),
            cursorWorktreesDirectory: home.appending(path: ".cursor/worktrees", directoryHint: .isDirectory),
            settingsDirectory: directory("CLEAN_CLAUDE_SETTINGS_DIR")
                ?? library.appending(path: "clean-claude", directoryHint: .isDirectory),
            scanRootsOverride: (scanRoots?.isEmpty ?? true) ? nil : scanRoots,
            now: now,
            tools: tools
        )
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
