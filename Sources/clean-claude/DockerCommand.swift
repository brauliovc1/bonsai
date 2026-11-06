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
        let report = await DockerScanner(environment: environment).scan()
        for warning in report.warnings {
            StandardError.write("warning: \(warning)")
        }
        print(DockerReportText(report: report, homeDirectory: environment.homeDirectory).render())
        guard prune else { return }

        guard let cleaner = DockerCleaner(environment: environment) else {
            StandardError.write("error: docker is not installed, so there is nothing to prune.")
            throw ExitCode.failure
        }
        print("")
        guard yes else {
            print("Would run: \(cleaner.commandLine)")
            print(Self.estimate(of: report))
            print("Nothing was changed. Add --yes to run it.")
            return
        }
        guard report.state == .running else {
            StandardError.write("error: Docker is not running. Start Docker Desktop, then run this again.")
            throw ExitCode.failure
        }

        print("Running: \(cleaner.commandLine)")
        let result = try await cleaner.run()
        if !result.output.isEmpty {
            print(result.output)
        }
        if result.timedOut {
            StandardError.write("error: docker did not finish in time and was stopped.")
        }
        if let freed = result.freedBytes {
            print("Freed on disk (measured): \(ByteFormatting.string(freed)).")
        }
        guard result.succeeded else {
            throw ExitCode(result.exitCode == 0 ? 1 : result.exitCode)
        }
        print("Docker Desktop hands the space back to macOS later, so this can be near zero right after a prune.")
    }

    private static func estimate(of report: DockerReport) -> String {
        guard report.state == .running else {
            return "Docker is not running, so there is no estimate and --yes would fail. Start Docker first."
        }
        return "docker system df lists \(ByteFormatting.string(report.reclaimableBytes)) as reclaimable; "
            + "this prune frees at most \(ByteFormatting.string(report.pruneCeilingBytes)) of it "
            + "(it keeps tagged images and volumes)."
    }
}
