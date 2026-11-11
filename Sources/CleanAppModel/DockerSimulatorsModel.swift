import CleanCore
import Foundation
import Observation

/// The Docker & Simulators screen: two sections, each with what it costs and one cleanup command behind a
/// sheet (`DockerSimulatorsModel+Docker`, `+Simulators`). Docker and Simulators run only through
/// `DockerCleaner.run(ifConfirmed:report:)` and `SimulatorCleaner.run(ifConfirmed:estimatedBytes:)`, which
/// write the log entry inside CleanCore; this model never starts docker or xcrun itself except through
/// their scanners.
@MainActor
@Observable
public final class DockerSimulatorsModel {
    public static let runtimesHint = "Remove runtimes in Xcode > Settings > Components."

    public enum DockerStatus: Sendable, Equatable {
        case unknown, notInstalled, notRunning, running
    }

    public let app: AppModel
    /// How docker and xcrun are run (tests pass a scripted runner).
    @ObservationIgnored let runner: CommandRunner
    @ObservationIgnored private let loop = ScanLoop()

    public internal(set) var docker: DockerReport?
    public internal(set) var simulators: SimulatorReport?
    public private(set) var isScanning = false
    public private(set) var lastScanAt: Date?

    // Docker sheet (DockerSimulatorsModel+Docker).
    public var isShowingDockerSheet = false
    public internal(set) var isPreparingDocker = false
    public internal(set) var dockerConfirmation: DockerPruneConfirmation?
    public internal(set) var isPruning = false
    public internal(set) var dockerReport: CleanupCommandReport?
    @ObservationIgnored var dockerSheetToken = 0

    // Simulators sheet (DockerSimulatorsModel+Simulators).
    public var isShowingSimulatorsSheet = false
    public internal(set) var isPreparingSimulators = false
    public internal(set) var simulatorsConfirmation: SimulatorsConfirmation?
    public internal(set) var isDeletingDevices = false
    public internal(set) var simulatorsReport: CleanupCommandReport?
    @ObservationIgnored var simulatorsSheetToken = 0

    public init(app: AppModel, runner: CommandRunner = .live) {
        self.app = app
        self.runner = runner
    }

    // MARK: - Docker

    public var dockerStatus: DockerStatus {
        switch docker?.state {
        case nil: .unknown
        case .notInstalled: .notInstalled
        case .notRunning: .notRunning
        case .running: .running
        }
    }

    public var dockerStatusText: String {
        switch dockerStatus {
        case .unknown: "Not scanned yet."
        case .notInstalled: "Docker isn't installed."
        case .notRunning: "Docker isn't running."
        case .running:
            "Docker Desktop is running" + (docker?.serverVersion.map { " (engine \($0))" } ?? "") + "."
        }
    }

    /// "Docker.raw: 20.2 GB on disk", whether or not the daemon is up.
    public var dockerDiskImageText: String? {
        docker?.diskImage.map { "Docker.raw: \(DisplayText.bytes($0.allocatedBytes)) on disk" }
    }

    /// Shown when the daemon is down: the disk image can only be cleaned from inside a running Docker.
    public var startDockerHint: String? {
        dockerStatus == .notRunning ? "Start Docker to clean." : nil
    }

    public var dockerUsage: [DockerUsageLine] { docker?.usage.map(DockerUsageLine.init) ?? [] }
    public var dockerWarnings: [String] { docker?.warnings ?? [] }

    /// Why the numbers are missing although Docker is running (`docker system df` failed); nil when they were read.
    public var dockerReadFailure: String? {
        dockerStatus == .running ? docker?.usageFailure : nil
    }

    /// What `docker system prune -f` could free at most; nil until Docker has answered, and when it
    /// answered but its numbers could not be read (never 0 then).
    public var dockerReclaimableBytes: Int64? {
        dockerStatus == .running && dockerReadFailure == nil ? docker?.pruneCeilingBytes : nil
    }

    /// Why Prune is disabled: `DockerReport.pruneBlocker`, or that nothing was scanned yet. nil when it may run.
    public var pruneDisabledReason: String? {
        guard let docker else { return "Not scanned yet." }
        return docker.pruneBlocker
    }

    public var canPrune: Bool { pruneDisabledReason == nil && app.cleanupQueue.task(for: Self.dockerResource) == nil && !app.isQuitting }

    // MARK: - Simulators

    public var simulatorsAvailable: Bool { simulators?.state == .available }
    public var noXcode: Bool { simulators?.state == .noXcode }
    public var devicesBytes: Int64? { simulators?.devicesBytes }
    public var cachesBytes: Int64? { simulators?.cachesBytes }
    public var unavailableDevices: [SimulatorDevice] { simulators?.unavailableDevices ?? [] }
    /// Why the unavailable devices are unknown although Xcode is there (`simctl list devices` failed).
    public var deviceListFailure: String? { simulatorsAvailable ? simulators?.deviceListFailure : nil }
    public var unavailableBytes: Int64? { simulatorsAvailable && deviceListFailure == nil ? simulators?.unavailableDevicesBytes : nil }
    public var runtimeLines: [SimulatorRuntimeLine] { simulators?.runtimes.map(SimulatorRuntimeLine.init) ?? [] }
    public var simulatorWarnings: [String] { simulators?.warnings ?? [] }

    public var canDeleteUnavailable: Bool {
        simulatorsAvailable && !unavailableDevices.isEmpty && app.cleanupQueue.task(for: Self.simulatorsResource) == nil && !app.isQuitting
    }

    // MARK: - Scanning

    /// Scans both sections now, or once more after the running scan; returns when that scan is done.
    public func refresh() async {
        await loop.run { [self] in
            isScanning = true
            async let dockerScan = DockerScanner(environment: app.environment, runner: runner).scan()
            async let simulatorScan = SimulatorScanner(environment: app.environment, runner: runner).scan()
            docker = await dockerScan
            simulators = await simulatorScan
            lastScanAt = app.environment.now()
            isScanning = false
        }
    }

    /// The first scan, when the screen first appears.
    public func loadIfNeeded() async {
        if docker == nil || simulators == nil { await refresh() }
    }
}
