import ArgumentParser
import CleanCore
import Foundation

struct SimulatorsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "simulators",
        abstract: "Show the iOS Simulator's disk use; with --delete-unavailable --yes, run xcrun simctl delete unavailable."
    )

    @Flag(
        name: .customLong("delete-unavailable"),
        help: "Prepare `xcrun simctl delete unavailable`. Without --yes it only prints the command and what it could free."
    )
    var deleteUnavailable = false

    @Flag(help: "Really run what --delete-unavailable describes.")
    var yes = false

    func validate() throws {
        if yes && !deleteUnavailable {
            throw ValidationError("--yes only goes with --delete-unavailable.")
        }
    }

    func run() async throws {
        let environment = CleanEnvironment.live()
        let report = await SimulatorScanner(environment: environment).scan()
        for warning in report.warnings {
            StandardError.write("warning: \(warning)")
        }
        print(SimulatorReportText(report: report, now: environment.now()).render())
        guard deleteUnavailable else { return }

        print("")
        guard let cleaner = SimulatorCleaner(environment: environment) else {
            StandardError.write("error: Xcode is not set up (xcode-select -p fails), so there is nothing to delete.")
            throw ExitCode.failure
        }

        if yes {
            print("Running: \(cleaner.commandLine)")
        }
        // Without --yes this returns nil and starts nothing.
        guard let result = try await cleaner.run(ifConfirmed: yes, estimatedBytes: report.unavailableDevicesBytes) else {
            print("Would run: \(cleaner.commandLine)")
            let count = report.unavailableDevices.count
            print("It would remove \(count) unavailable device(s), about \(ByteFormatting.string(report.unavailableDevicesBytes)).")
            print("Nothing was changed. Add --yes to run it.")
            return
        }

        if !result.output.isEmpty {
            print(result.output)
        }
        if result.timedOut {
            StandardError.write("error: simctl did not finish in time and was stopped; some devices may be left.")
        }
        if let freed = result.freedBytes {
            print("Freed on disk so far (measured): \(ByteFormatting.string(freed)).")
        }
        if let logError = result.logError {
            StandardError.write("error: \(logError)")
        }
        if result.exitStatus != 0 {
            throw ExitCode(result.exitStatus)
        }
    }
}
