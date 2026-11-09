import Foundation

/// Where the tool-cache scanner and cleaner get a fresh `ProcessList` from: `/bin/ps` in production, a script
/// in tests (so a test can have an owner start between the scan and the clean).
public struct ProcessSource: Sendable {
    public var capture: @Sendable () async -> ProcessList

    public init(_ capture: @escaping @Sendable () async -> ProcessList) {
        self.capture = capture
    }

    /// `/bin/ps` through `runner`. `cursorAppRunning`: the app's NSWorkspace check for Cursor's bundle id;
    /// nil in the CLI, which has only ps.
    public static func live(
        runner: CommandRunner = .live,
        cursorAppRunning: (@Sendable () async -> Bool)? = nil
    ) -> ProcessSource {
        ProcessSource { await ProcessList.capture(runner: runner, cursorAppRunning: cursorAppRunning) }
    }
}
