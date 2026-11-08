import ArgumentParser
import CleanCore
import Foundation

struct DockerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "docker",
        abstract: "Show where Docker Desktop's disk space goes; with --prune --yes, run docker system prune -f."
    )

    @Flag(help: "Prepare `docker system prune -f`. Without --yes it only prints the command and what it could free.")
    var prune = false

    @Flag(help: "Really run what --prune describes.")
    var yes = false

    func validate() throws {
        if yes && !prune {
            throw ValidationError("--yes only goes with --prune.")
        }
    }

    func run() async throws {
        let environment = CleanEnvironment.live()
        let lock = try CommandContext.holdCleanupLock(if: yes, environment: environment)
        defer { lock?.release() }
        let report = await DockerScanner(environment: environment).scan()
        for warning in report.warnings {
            StandardError.write("warning: \(warning)")
        }
        print(DockerReportText(report: report, homeDirectory: environment.homeDirectory).render())
        guard prune else { return }

        print("")
        if let blocker = report.pruneBlocker {
            StandardError.write("error: \(blocker)")
            throw ExitCode.failure
        }
        guard let cleaner = DockerCleaner(environment: environment) else {
            StandardError.write("error: docker is not installed, so there is nothing to prune.")
            throw ExitCode.failure
        }

        if yes {
            print("Running: \(cleaner.commandLine)")
        }
        // Without --yes this returns nil and starts nothing.
        guard let result = try await cleaner.run(ifConfirmed: yes, report: report) else {
            print("Would run: \(cleaner.commandLine)")
            print(Self.estimate(of: report))
            print("Nothing was changed. Add --yes to run it.")
            return
        }

        if !result.output.isEmpty {
            print(result.output)
        }
        if result.timedOut {
            StandardError.write("error: the docker command did not finish in time and was stopped. "
                + "The Docker daemon may still be working, so the freed-space figure below can be incomplete.")
        }
        if let freed = result.freedBytes {
            print("Freed on disk so far (measured): \(ByteFormatting.string(freed)).")
        }
        if let logError = result.logError {
            StandardError.write("error: \(logError)")
        }
        if result.succeeded {
            print("Docker Desktop hands the space back to macOS later, so this can be near zero right after a prune.")
        }
        if result.exitStatus != 0 {
            throw ExitCode(result.exitStatus)
        }
    }

    private static func estimate(of report: DockerReport) -> String {
        "docker system df lists \(ByteFormatting.string(report.reclaimableBytes)) as reclaimable. "
            + "This prune removes all stopped containers, unused networks, dangling images and unused build cache, "
            + "and frees at most \(ByteFormatting.string(report.pruneCeilingBytes)) of that. "
            + "It keeps tagged images and volumes."
    }
}
