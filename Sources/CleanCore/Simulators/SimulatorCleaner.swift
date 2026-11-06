import Foundation

/// Runs `xcrun simctl delete unavailable`: the only simulator command in the codebase that changes
/// anything. It removes devices whose runtime is gone; installed runtimes are never touched.
///
/// Nothing here is started by a scan, and the only public way to run it is `run(ifConfirmed:)`.
public struct SimulatorCleaner: Sendable {
    /// Run through `xcrun`.
    public static let deleteUnavailableArguments = ["simctl", "delete", "unavailable"]

    public var xcrun: URL
    public var runner: CommandRunner
    public var freeSpace: FreeSpaceProbe
    public var timeout: Duration

    /// `runner` has no default on purpose: a test that forgets it must not reach the real xcrun.
    public init(
        xcrun: URL,
        runner: CommandRunner,
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

    /// Deletes only when `confirmed` is true; otherwise returns nil and runs nothing. Throws only when
    /// xcrun cannot be started.
    public func run(ifConfirmed confirmed: Bool) async throws -> CleanupCommandResult? {
        guard confirmed else { return nil }
        return try await run()
    }

    /// Starts the delete and measures what it freed. No checks: callers go through `run(ifConfirmed:)`.
    func run() async throws -> CleanupCommandResult {
        try await CleanupCommandResult.measuredRun(
            executable: xcrun,
            arguments: Self.deleteUnavailableArguments,
            timeout: timeout,
            runner: runner,
            freeSpace: freeSpace
        )
    }
}
