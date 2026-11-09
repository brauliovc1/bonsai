import Foundation

/// The PLAN §4.6 table as one constant: every tool cache and piece of Cursor's data Bonsai shows, with exactly
/// what cleaning it deletes, what it never touches, and which programs must not be running. Nothing outside
/// these paths is ever deleted. Package stores that hard-link into projects (pnpm) and generic app caches in
/// `~/Library/Caches` are deliberately not here.
public enum ToolCacheCatalog {
    /// Cursor's bundle id, for the app's NSWorkspace check.
    public static let cursorBundleID = "com.todesktop.230313mzl4w4u92"

    static let cursor = "Library/Application Support/Cursor"
    static let globalStorage = cursor + "/User/globalStorage"
    static let agentCLI = globalStorage + "/anysphere.cursor-agent-worker/agent-cli/.local"

    public static let entries: [ToolCacheEntry] = packageEntries + cursorEntries

    public static func entry(id: String) -> ToolCacheEntry? {
        entries.first { $0.id == id }
    }

    /// The ids `caches clean` accepts.
    public static var cleanableIDs: [String] {
        entries.filter(\.isCleanable).map(\.id)
    }

    static let packageEntries: [ToolCacheEntry] = [
        ToolCacheEntry(
            id: "npm", name: "npm", section: .packages,
            paths: [".npm/_cacache", ".npm/_npx"], never: [".npm"],
            owners: [
                ToolOwner("npm", [.command(["npm"]), .argumentName(["npm-cli.js"])]),
                ToolOwner("npx", [.command(["npx"]), .argumentName(["npx-cli.js"])]),
            ],
            note: "npm downloads packages again on the next install."
        ),
        ToolCacheEntry(
            id: "yarn", name: "Yarn", section: .packages,
            paths: ["Library/Caches/Yarn", ".yarn/berry/cache"], never: [".yarn"],
            owners: [ToolOwner("Yarn", [
                .command(["yarn", "yarnpkg"]), .argumentName(["yarn.js", "yarn.cjs"]), .argumentContains("/.yarn/releases/"),
            ])],
            note: "Yarn downloads packages again on the next install."
        ),
        ToolCacheEntry(
            id: "pip", name: "pip", section: .packages,
            paths: ["Library/Caches/pip"],
            owners: [ToolOwner("pip", [.command(["pip", "pip3"])])],
            note: "pip downloads packages again on the next install."
        ),
        ToolCacheEntry(
            id: "uv", name: "uv", section: .packages,
            paths: [".cache/uv"], never: [".cache"],
            owners: [ToolOwner("uv", [.command(["uv", "uvx"])])],
            note: "uv downloads packages again when it needs them."
        ),
        ToolCacheEntry(
            id: "pub", name: "Dart/Flutter pub", section: .packages,
            paths: [".pub-cache/hosted", ".pub-cache/git"], never: [".pub-cache/bin", ".pub-cache/global_packages"],
            owners: [
                ToolOwner("dart", [.command(["dart", "dartaotruntime"])]),
                ToolOwner("Flutter", [.command(["flutter"]), .argumentContains("flutter_tools")]),
            ],
            note: "Packages download again; Flutter projects need `flutter pub get`. Globally activated tools stay."
        ),
        ToolCacheEntry(
            id: "cocoapods", name: "CocoaPods", section: .packages,
            paths: ["Library/Caches/CocoaPods"],
            owners: [ToolOwner("pod", [.command(["pod"])])],
            note: "CocoaPods downloads pods again on the next `pod install`."
        ),
        ToolCacheEntry(
            id: "homebrew", name: "Homebrew downloads", section: .packages,
            paths: ["Library/Caches/Homebrew"],
            owners: [ToolOwner("brew", [.command(["brew", "brew.sh", "brew.rb"])])],
            note: "Installed formulae stay; Homebrew downloads again when it needs to."
        ),
        ToolCacheEntry(
            id: "gradle", name: "Gradle", section: .packages,
            paths: [".gradle/caches"], never: [".gradle"],
            owners: [ToolOwner("Gradle", [
                .command(["gradle", "gradlew"]), .argumentContains("GradleDaemon"), .argumentContains("GradleMain"),
                .argumentContains("GradleWrapperMain"),
            ])],
            note: "Gradle downloads dependencies again on the next build, which is slower."
        ),
        ToolCacheEntry(
            id: "swiftpm", name: "SwiftPM", section: .packages,
            paths: ["Library/Caches/org.swift.swiftpm"],
            owners: [
                ToolOwner("swift-build", [.command(["swift-build", "swift-package", "swift-test", "swift-run"])]),
                ToolOwner("xcodebuild", [.command(["xcodebuild"])]),
                ToolOwner("Xcode", [.command(["xcode"])]),
            ],
            note: "Swift packages are fetched again on the next build or resolve."
        ),
        ToolCacheEntry(
            id: "go-build", name: "Go build", section: .packages,
            paths: ["Library/Caches/go-build"],
            owners: [ToolOwner("go", [.command(["go", "gopls"])])],
            note: "Go rebuilds it on the next build, which is slower."
        ),
        ToolCacheEntry(
            id: "playwright", name: "Playwright browsers", section: .packages,
            paths: ["Library/Caches/ms-playwright"],
            owners: [ToolOwner("Playwright", [.argumentContains("playwright")])],
            note: "Run `npx playwright install` to get the browsers back."
        ),
        ToolCacheEntry(
            id: "mongodb-binaries", name: "MongoDB test binaries", section: .packages,
            paths: [".cache/mongodb-binaries"], never: [".cache"],
            owners: [
                ToolOwner("mongod", [.command(["mongod", "mongos"])]),
                ToolOwner("mongodb-memory-server", [.argumentContains("mongodb-memory-server")]),
            ],
            note: "Tests download it again, ~300 MB."
        ),
        ToolCacheEntry(
            id: "xcode-cache", name: "Xcode cache", section: .packages,
            paths: ["Library/Caches/com.apple.dt.Xcode"],
            owners: [ToolOwner("Xcode", [.command(["xcode"])]), ToolOwner("xcodebuild", [.command(["xcodebuild"])])],
            note: "Xcode rebuilds it the next time it opens."
        ),
    ]

    static let cursorEntries: [ToolCacheEntry] = [
        ToolCacheEntry(
            id: "cursor-agent-versions", name: "Cursor: old agent versions", section: .cursor,
            deletion: .cursorAgentVersions,
            paths: [CursorAgentVersions.versionsPath], never: [CursorAgentVersions.linkPath],
            owners: [.cursor, ToolOwner("cursor-agent", [.command(["cursor-agent"]), .argumentContains("cursor-agent")])],
            note: "Old copies of Cursor's agent command-line tool; the one in use and the newest stay."
        ),
        ToolCacheEntry(
            id: "cursor-state-backup", name: "Cursor: old state backup", section: .cursor,
            deletion: .cursorStateBackup,
            paths: [CursorStateBackup.backupPath],
            never: [CursorStateBackup.statePath, CursorStateBackup.statePath + "-wal", CursorStateBackup.statePath + "-shm"],
            owners: [.cursor],
            note: "Cursor's spare copy of its database; your current chats stay in `state.vscdb`."
        ),
        ToolCacheEntry(
            id: "cursor-caches", name: "Cursor: app caches", section: .cursor,
            paths: ["Cache", "CachedData", "Code Cache", "GPUCache", "CachedExtensionVSIXs", "logs"].map { cursor + "/" + $0 },
            never: [cursor],
            owners: [.cursor],
            note: "Cursor rebuilds its caches and starts new logs as it runs."
        ),
        displayOnly("cursor-state", "Cursor: chats and settings", "Your chats and settings",
                    [CursorStateBackup.statePath, CursorStateBackup.statePath + "-wal", CursorStateBackup.statePath + "-shm"]),
        displayOnly("cursor-snapshots", "Cursor: snapshots", "Cursor's checkpoints", [cursor + "/snapshots"]),
        displayOnly("cursor-workspace-storage", "Cursor: workspace storage", "Per-project chats and state",
                    [cursor + "/User/workspaceStorage"]),
        displayOnly("cursor-chats", "Cursor agent: chats", "Cursor agent's chats", [".cursor/chats"]),
        displayOnly("cursor-projects", "Cursor agent: projects", "Cursor agent's project data", [".cursor/projects"]),
        displayOnly("cursor-extensions", "Cursor: extensions", "Your extensions", [".cursor/extensions"]),
    ]

    private static func displayOnly(_ id: String, _ name: String, _ reason: String, _ paths: [String]) -> ToolCacheEntry {
        ToolCacheEntry(id: id, name: name, section: .cursor, deletion: .none(reason: reason), paths: paths, owners: [], note: reason + ".")
    }
}
