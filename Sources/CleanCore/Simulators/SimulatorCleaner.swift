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

    /// Why `run(ifConfirmed:estimatedBytes:onlyDeleting:)` ran nothing.
    public enum Refusal: Error, Sendable, Hashable, CustomStringConvertible {
        /// `simctl list devices` failed, so what the delete would remove is unknown.
        case listFailed(String)
        /// The unavailable devices are not exactly the confirmed ones (UDIDs that appeared, UDIDs that are gone).
        case listChanged(added: [String], gone: [String])

        public var description: String {
            switch self {
            case .listFailed(let why):
                return "xcrun could not list the devices (\(why)), so nothing was deleted."
            case .listChanged(let added, let gone):
                var parts: [String] = []
                if !added.isEmpty { parts.append("\(added.count) more would be deleted now") }
                if !gone.isEmpty { parts.append("\(gone.count) listed are no longer unavailable") }
                return "The list of unavailable devices changed since you confirmed it (\(parts.joined(separator: ", "))), "
                    + "so nothing was deleted; review it again."
            }
        }
    }

    /// Like `run(ifConfirmed:estimatedBytes:)`, but `simctl delete unavailable` takes no argument that
    /// limits it, so the unavailable devices are listed again right before it starts (`simctl list
    /// devices`, nothing else: no sizes) and it runs only when they are exactly `expected`. Throws
    /// `Refusal` otherwise, with nothing run.
    public func run(
        ifConfirmed confirmed: Bool,
        estimatedBytes: Int64? = nil,
        onlyDeleting expected: [SimulatorDevice]
    ) async throws -> CleanupCommandResult? {
        guard confirmed else { return nil }
        let current = try await unavailableUDIDs()
        let confirmedUDIDs = Set(expected.map(\.udid))
        guard current == confirmedUDIDs else {
            throw Refusal.listChanged(
                added: current.subtracting(confirmedUDIDs).sorted(),
                gone: confirmedUDIDs.subtracting(current).sorted()
            )
        }
        // Nothing runs between the comparison above and the start of the delete.
        return try await run(estimatedBytes: estimatedBytes)
    }

    private func unavailableUDIDs() async throws -> Set<String> {
        let result: ProcessResult
        do {
            result = try await runner.run(xcrun, SimulatorScanner.devicesArguments, timeout: .seconds(30))
        } catch {
            throw Refusal.listFailed("\(error)")
        }
        guard result.succeeded else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw Refusal.listFailed(result.timedOut ? "timed out" : "exit \(result.exitCode)" + (message.isEmpty ? "" : ": \(message)"))
        }
        do {
            return Set(try SimctlParser.unavailableDevices(from: result.stdout).map(\.udid))
        } catch {
            throw Refusal.listFailed("\(error)")
        }
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
