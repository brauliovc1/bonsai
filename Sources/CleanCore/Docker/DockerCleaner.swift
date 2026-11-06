import Foundation

/// Runs `docker system prune -f`: the only docker command in the codebase that changes anything.
///
/// No `-a` (tagged images stay) and no `--volumes` (volumes stay). Callers decide when to run it;
/// nothing here is started by a scan.
public struct DockerCleaner: Sendable {
    public static let pruneArguments = ["system", "prune", "-f"]

    public var docker: URL
    public var runner: CommandRunner
    public var freeSpace: FreeSpaceProbe
    /// A prune with a big build cache can take minutes.
    public var timeout: Duration

    public init(
        docker: URL,
        runner: CommandRunner = .live,
        freeSpace: FreeSpaceProbe,
        timeout: Duration = .seconds(900)
    ) {
        self.docker = docker
        self.runner = runner
        self.freeSpace = freeSpace
        self.timeout = timeout
    }

    /// nil when docker is not installed. Free space is read from the volume of the home folder.
    public init?(environment: CleanEnvironment, runner: CommandRunner = .live) {
        guard let docker = environment.tools.docker else { return nil }
        self.init(
            docker: docker,
            runner: runner,
            freeSpace: .volume(containing: environment.homeDirectory)
        )
    }

    /// The command as text, for showing what would run.
    public var commandLine: String {
        CommandLineDisplay.string(executable: docker.path, arguments: Self.pruneArguments)
    }

    /// Runs the prune and measures what it freed. Throws only when docker cannot be started.
    public func run() async throws -> CleanupCommandResult {
        try await CleanupCommandResult.measuredRun(
            executable: docker,
            arguments: Self.pruneArguments,
            timeout: timeout,
            runner: runner,
            freeSpace: freeSpace,
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
