import Foundation

/// Runs `docker system prune -f`: the only docker command in the codebase that changes anything.
///
/// It removes stopped containers, unused networks, dangling images and unused build cache. No `-a`
/// (tagged images stay) and no `--volumes` (volumes stay). Nothing here is started by a scan, and the
/// only public way to run it is `run(ifConfirmed:report:)`.
public struct DockerCleaner: Sendable {
    public static let pruneArguments = ["system", "prune", "-f"]

    /// The prune was asked for but must not run (see `DockerReport.pruneBlocker`).
    public struct Refused: Error, Sendable, CustomStringConvertible {
        public var description: String
    }

    public var docker: URL
    public var runner: CommandRunner
    public var freeSpace: FreeSpaceProbe
    /// Every prune that ran is logged here (`dockerPrune`).
    public var log: RemovalLog
    /// A prune with a big build cache can take minutes.
    public var timeout: Duration
    public var now: @Sendable () -> Date

    /// `runner` and `log` have no default on purpose: a test that forgets them must not reach the real
    /// docker or the real log.
    public init(
        docker: URL,
        runner: CommandRunner,
        freeSpace: FreeSpaceProbe,
        log: RemovalLog,
        timeout: Duration = .seconds(900),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.docker = docker
        self.runner = runner
        self.freeSpace = freeSpace
        self.log = log
        self.timeout = timeout
        self.now = now
    }

    /// nil when docker is not installed. Free space is read from the volume of the home folder; the log
    /// is the environment's.
    public init?(environment: CleanEnvironment, runner: CommandRunner = .live) {
        guard let docker = environment.tools.docker else { return nil }
        self.init(
            docker: docker,
            runner: runner,
            freeSpace: .volume(containing: environment.homeDirectory),
            log: RemovalLog(environment: environment),
            now: environment.now
        )
    }

    /// The command as text, for showing what would run.
    public var commandLine: String {
        CommandLineDisplay.string(executable: docker.path, arguments: Self.pruneArguments)
    }

    /// Prunes only when `confirmed` is true and `report` says the daemon is Docker Desktop and running.
    /// Returns nil, running nothing, when not confirmed; throws `Refused` when confirmed but blocked.
    /// Throws other errors only when docker cannot be started. A prune that ran is logged, with
    /// `report.pruneCeilingBytes` as the estimate; `logError` says when the entry could not be written.
    public func run(ifConfirmed confirmed: Bool, report: DockerReport) async throws -> CleanupCommandResult? {
        guard confirmed else { return nil }
        if let reason = report.pruneBlocker {
            throw Refused(description: reason)
        }
        return try await run(estimatedBytes: report.pruneCeilingBytes)
    }

    /// Starts the prune, measures what it freed and logs it. No checks: callers go through
    /// `run(ifConfirmed:report:)`.
    func run(estimatedBytes: Int64?) async throws -> CleanupCommandResult {
        try await CleanupCommandResult.measuredRun(
            executable: docker,
            arguments: Self.pruneArguments,
            timeout: timeout,
            runner: runner,
            freeSpace: freeSpace,
            logging: CleanupLogging(log: log, action: .dockerPrune, estimatedBytes: estimatedBytes, now: now),
            reportedBytes: Self.reclaimedSpace
        )
    }

    /// The `Total reclaimed space: 1.2GB` line docker prints at the end of a prune.
    static func reclaimedSpace(in output: String) -> Int64? {
        let marker = "Total reclaimed space:"
        guard let line = output.split(whereSeparator: \.isNewline).last(where: { $0.contains(marker) }),
              let range = line.range(of: marker)
        else { return nil }
        return DockerSizeParser.bytes(from: String(line[range.upperBound...]))
    }
}
