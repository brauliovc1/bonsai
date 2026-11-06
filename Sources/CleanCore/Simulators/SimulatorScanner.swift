import Foundation

/// Sizes of the CoreSimulator folders, the devices that can no longer boot, and the installed runtimes.
/// Read-only: only `simctl list` and `simctl runtime list` run here.
public struct SimulatorScanner: Sendable {
    public var environment: CleanEnvironment
    public var runner: CommandRunner
    public var timeout: Duration

    public init(environment: CleanEnvironment, runner: CommandRunner = .live, timeout: Duration = .seconds(30)) {
        self.environment = environment
        self.runner = runner
        self.timeout = timeout
    }

    static let devicesArguments = ["simctl", "list", "devices", "-j"]
    static let runtimesArguments = ["simctl", "runtime", "list", "-j"]

    /// `<home>/Library/Developer/CoreSimulator`.
    private var coreSimulator: URL {
        environment.homeDirectory.appending(path: "Library/Developer/CoreSimulator", directoryHint: .isDirectory)
    }

    public func scan() async -> SimulatorReport {
        // `xcode-select -p` failing (or no xcrun) means no Xcode: do not touch the /usr/bin shims.
        guard environment.tools.developerToolsInstalled, let xcrun = environment.tools.xcrun else {
            return SimulatorReport(state: .noXcode)
        }

        async let devices = unavailableDevices(xcrun: xcrun)
        async let runtimes = installedRuntimes(xcrun: xcrun)
        async let sizes = folderSizes()
        let (foundDevices, deviceWarnings) = await devices
        let (foundRuntimes, runtimeWarnings) = await runtimes
        let measured = await sizes

        return SimulatorReport(
            state: .available,
            devicesBytes: measured.devices,
            cachesBytes: measured.caches,
            unavailableDevices: foundDevices,
            runtimes: foundRuntimes,
            warnings: deviceWarnings + runtimeWarnings + measured.warnings,
            deviceListFailure: deviceWarnings.first
        )
    }

    private func unavailableDevices(xcrun: URL) async -> ([SimulatorDevice], [String]) {
        await listing(xcrun: xcrun, arguments: Self.devicesArguments, label: "simctl list devices") {
            try SimctlParser.unavailableDevices(from: $0)
        }
    }

    private func installedRuntimes(xcrun: URL) async -> ([SimulatorRuntime], [String]) {
        await listing(xcrun: xcrun, arguments: Self.runtimesArguments, label: "simctl runtime list") {
            try SimctlParser.runtimes(from: $0)
        }
    }

    /// Runs one simctl listing and parses its stdout; any failure becomes a warning and an empty list.
    private func listing<Item: Sendable>(
        xcrun: URL,
        arguments: [String],
        label: String,
        parse: (Data) throws -> [Item]
    ) async -> ([Item], [String]) {
        do {
            let result = try await runner.run(xcrun, arguments, timeout: timeout)
            guard result.succeeded else {
                let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let reason = result.timedOut ? "timed out" : "failed (exit \(result.exitCode))"
                return ([], ["\(label) \(reason)" + (message.isEmpty ? "" : ": \(message)")])
            }
            return (try parse(result.stdout), [])
        } catch {
            return ([], ["\(label): \(error)"])
        }
    }

    private func folderSizes() async -> (devices: Int64?, caches: Int64?, warnings: [String]) {
        guard let du = environment.tools.du else {
            return (nil, nil, ["/usr/bin/du not found; CoreSimulator sizes skipped"])
        }
        let devices = coreSimulator.appending(path: "Devices", directoryHint: .isDirectory)
        let caches = coreSimulator.appending(path: "Caches", directoryHint: .isDirectory)
        let measured = await DirectorySizer(du: du).sizes(of: [devices, caches])
        return (measured.sizes[devices.path], measured.sizes[caches.path], measured.issues.map(\.description))
    }
}
