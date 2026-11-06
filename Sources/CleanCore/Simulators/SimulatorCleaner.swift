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
    /// Every delete that ran is logged here (`simulatorsDeleteUnavailable`).
    public var log: RemovalLog
    public var timeout: Duration
    public var now: @Sendable () -> Date

    /// `runner` and `log` have no default on purpose: a test that forgets them must not reach the real
    /// xcrun or the real log.
    public init(
        xcrun: URL,
        runner: CommandRunner,
        freeSpace: FreeSpaceProbe,
        log: RemovalLog,
        timeout: Duration = .seconds(600),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.xcrun = xcrun
        self.runner = runner
        self.freeSpace = freeSpace
        self.log = log
        self.timeout = timeout
        self.now = now
    }

    /// nil when there is no Xcode (`xcode-select -p` failed or no xcrun). Free space is read from the
    /// volume of the home folder; the log is the environment's.
    public init?(environment: CleanEnvironment, runner: CommandRunner = .live) {
        guard environment.tools.developerToolsInstalled, let xcrun = environment.tools.xcrun else { return nil }
        self.init(
            xcrun: xcrun,
            runner: runner,
            freeSpace: .volume(containing: environment.homeDirectory),
            log: RemovalLog(environment: environment),
            now: environment.now
        )
    }

    /// The command as text, for showing what would run.
    public var commandLine: String {
        CommandLineDisplay.string(executable: xcrun.path, arguments: Self.deleteUnavailableArguments)
    }

    /// Deletes only when `confirmed` is true; otherwise returns nil and runs nothing. Throws only when
    /// xcrun cannot be started. A delete that ran is logged with `estimatedBytes` (pass
    /// `SimulatorReport.unavailableDevicesBytes`); `logError` says when the entry could not be written.
    public func run(ifConfirmed confirmed: Bool, estimatedBytes: Int64? = nil) async throws -> CleanupCommandResult? {
        guard confirmed else { return nil }
        return try await run(estimatedBytes: estimatedBytes)
    }

    /// Starts the delete, measures what it freed and logs it. No checks: callers go through
    /// `run(ifConfirmed:)`.
    func run(estimatedBytes: Int64?) async throws -> CleanupCommandResult {
        try await CleanupCommandResult.measuredRun(
            executable: xcrun,
            arguments: Self.deleteUnavailableArguments,
            timeout: timeout,
            runner: runner,
            freeSpace: freeSpace,
            logging: CleanupLogging(log: log, action: .simulatorsDeleteUnavailable, estimatedBytes: estimatedBytes, now: now)
        )
    }
}
