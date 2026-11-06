import Foundation

/// Runs `xcrun simctl delete unavailable`: the only simulator command in the codebase that changes
/// anything. It removes devices whose runtime is gone; installed runtimes are never touched.
///
/// Callers decide when to run it; nothing here is started by a scan.
public struct SimulatorCleaner: Sendable {
    /// Run through `xcrun`.
    public static let deleteUnavailableArguments = ["simctl", "delete", "unavailable"]

    public var xcrun: URL
    public var runner: CommandRunner
    public var freeSpace: FreeSpaceProbe
    public var timeout: Duration

    public init(
        xcrun: URL,
        runner: CommandRunner = .live,
        freeSpace: FreeSpaceProbe,
        timeout: Duration = .seconds(600)
    ) {
        self.xcrun = xcrun
        self.runner = runner
        self.freeSpace = freeSpace
        self.timeout = timeout
    }

    /// nil when there is no Xcode (`xcode-select -p` failed or no xcrun). Free space is read from the
    /// volume of the home folder.
    public init?(environment: CleanEnvironment, runner: CommandRunner = .live) {
        guard environment.tools.developerToolsInstalled, let xcrun = environment.tools.xcrun else { return nil }
        self.init(
            xcrun: xcrun,
            runner: runner,
            freeSpace: .volume(containing: environment.homeDirectory)
        )
    }

    /// The command as text, for showing what would run.
    public var commandLine: String {
        CommandLineDisplay.string(executable: xcrun.path, arguments: Self.deleteUnavailableArguments)
    }

    /// Runs the delete and measures what it freed. Throws only when xcrun cannot be started.
    public func run() async throws -> CleanupCommandResult {
        try await CleanupCommandResult.measuredRun(
            executable: xcrun,
            arguments: Self.deleteUnavailableArguments,
            timeout: timeout,
            runner: runner,
            freeSpace: freeSpace
        )
    }
}
