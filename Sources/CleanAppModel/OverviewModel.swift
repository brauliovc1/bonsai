import CleanCore
import Foundation
import Observation

/// The Overview: free space, what could be reclaimed in each category (summed from the other screens'
/// models, never measured again here) with a button that jumps to the screen that does it, and Refresh.
@MainActor
@Observable
public final class OverviewModel {
    /// Light clean counts worktrees idle at least this many days.
    public static let lightCleanIdleDays = 7

    public let app: AppModel
    public let worktrees: WorktreesModel
    public let projects: ProjectsModel
    public let derivedData: DerivedDataModel
    public let dockerSimulators: DockerSimulatorsModel
    public let autoMode: AutoModeModel
    public let navigation: NavigationModel

    public init(
        app: AppModel,
        worktrees: WorktreesModel,
        projects: ProjectsModel,
        derivedData: DerivedDataModel,
        dockerSimulators: DockerSimulatorsModel,
        autoMode: AutoModeModel,
        navigation: NavigationModel
    ) {
        self.app = app
        self.worktrees = worktrees
        self.projects = projects
        self.derivedData = derivedData
        self.dockerSimulators = dockerSimulators
        self.autoMode = autoMode
        self.navigation = navigation
    }

    /// The auto mode row: off / report-only until <date> / on.
    public var autoModeText: String { autoMode.statusText }

    /// The auto mode row's second line: the last run and the next.
    public var autoModeDetail: String {
        autoMode.isRunning ? "Running now…" : autoMode.lastRunText + " " + autoMode.nextRunText
    }

    public var disk: DiskSpaceModel { app.disk }

    /// True while anything the Overview sums is being scanned.
    public var isRefreshing: Bool {
        app.isScanning || derivedData.isScanning || dockerSimulators.isScanning || projects.isScanning
    }

    // MARK: - Rows

    public var rows: [OverviewRow] {
        OverviewRow.Kind.allCases.map(row)
    }

    public func row(_ kind: OverviewRow.Kind) -> OverviewRow {
        switch kind {
        case .autoReadyWorktrees: worktreeRow(kind, title: "Worktrees ready for auto mode", status: .autoReady)
        case .safeWorktrees: worktreeRow(kind, title: "Other safe worktrees", status: .safe)
        case .lightClean: lightCleanRow()
        case .projectFolders: projectFoldersRow()
        case .orphanedDerivedData: derivedDataRow()
        case .docker: dockerRow()
        case .simulators: simulatorsRow()
        }
    }

    /// Opens the screen behind a row.
    public func jump(to kind: OverviewRow.Kind) {
        navigation.show(row(kind).destination)
    }

    private enum WorktreeGroup { case autoReady, safe }

    private func worktreeRow(_ kind: OverviewRow.Kind, title: String, status group: WorktreeGroup) -> OverviewRow {
        guard app.scan != nil else {
            return OverviewRow(kind: kind, title: title, detail: app.problem ?? "Not scanned yet.", bytes: nil, destination: .worktrees)
        }
        let matching = app.assessments.filter { assessment in
            switch (assessment.status, group) {
            case (.autoReady, .autoReady), (.safe, .safe): true
            default: false
            }
        }
        let bytes = matching.compactMap(\.estimatedBytes).reduce(0, +)
        return OverviewRow(kind: kind, title: title, detail: DisplayText.worktrees(matching.count), bytes: bytes, destination: .worktrees)
    }

    private func lightCleanRow() -> OverviewRow {
        let title = "Light clean: dependencies of worktrees idle \(Self.lightCleanIdleDays)+ days"
        let idle = worktrees.allRows.filter { ($0.idleDays ?? -1) >= Self.lightCleanIdleDays }
        let measured = idle.filter { $0.dependencyBytes != nil }
        if worktrees.isMeasuringDependencies {
            return OverviewRow(kind: .lightClean, title: title, detail: "Measuring…", bytes: nil, destination: .worktrees)
        }
        if !worktrees.hasRequestedDependencies {
            return OverviewRow(kind: .lightClean, title: title, detail: "Measured when you open Worktrees.", bytes: nil, destination: .worktrees)
        }
        let bytes = measured.compactMap(\.dependencyBytes).reduce(0, +)
        let detail = "\(DisplayText.worktrees(measured.count)) with folders to delete. Overlaps the rows above: "
            + "removing a whole worktree removes its dependencies too."
        return OverviewRow(kind: .lightClean, title: title, detail: detail, bytes: bytes, destination: .worktrees)
    }

    private func projectFoldersRow() -> OverviewRow {
        let title = "Project build folders"
        guard projects.report != nil else {
            let detail = projects.isScanning ? "Measuring…" : "Measured when you open Project folders."
            return OverviewRow(kind: .projectFolders, title: title, detail: detail, bytes: nil, destination: .projects)
        }
        let idle = projects.idleTotal
        let detail = "In \(idle.count) idle \(idle.count == 1 ? "project" : "projects") (\(projects.threshold)+ days, nothing running inside)."
        return OverviewRow(kind: .projectFolders, title: title, detail: detail, bytes: idle.bytes, destination: .projects)
    }

    private func derivedDataRow() -> OverviewRow {
        let title = "Orphaned DerivedData"
        guard derivedData.report != nil else {
            return OverviewRow(kind: .orphanedDerivedData, title: title, detail: "Not scanned yet.", bytes: nil, destination: .derivedData)
        }
        if let refusal = derivedData.refusal {
            return OverviewRow(kind: .orphanedDerivedData, title: title, detail: refusal, bytes: nil, destination: .derivedData)
        }
        let count = derivedData.orphanRows.count
        return OverviewRow(
            kind: .orphanedDerivedData, title: title, detail: DisplayText.folders(count),
            bytes: derivedData.orphanBytes, destination: .derivedData
        )
    }

    private func dockerRow() -> OverviewRow {
        let title = "Docker reclaimable"
        let detail: String
        switch dockerSimulators.dockerStatus {
        case .unknown: detail = "Not scanned yet."
        case .notInstalled: detail = "Docker isn't installed."
        case .notRunning: detail = "Docker isn't running."
        case .running:
            detail = dockerSimulators.dockerReadFailure.map { "Couldn't read: \($0)." } ?? "At most: volumes and tagged images stay."
        }
        return OverviewRow(
            kind: .docker, title: title, detail: detail,
            bytes: dockerSimulators.dockerReclaimableBytes, destination: .dockerSimulators
        )
    }

    private func simulatorsRow() -> OverviewRow {
        let title = "Unavailable simulators"
        guard dockerSimulators.simulators != nil else {
            return OverviewRow(kind: .simulators, title: title, detail: "Not scanned yet.", bytes: nil, destination: .dockerSimulators)
        }
        if dockerSimulators.noXcode {
            return OverviewRow(kind: .simulators, title: title, detail: "Xcode isn't installed.", bytes: nil, destination: .dockerSimulators)
        }
        if let failure = dockerSimulators.deviceListFailure {
            return OverviewRow(
                kind: .simulators, title: title, detail: "Couldn't read: \(failure).", bytes: nil, destination: .dockerSimulators
            )
        }
        let count = dockerSimulators.unavailableDevices.count
        let detail = count == 1 ? "1 device" : "\(count) devices"
        return OverviewRow(
            kind: .simulators, title: title, detail: detail,
            bytes: dockerSimulators.unavailableBytes, destination: .dockerSimulators
        )
    }

    // MARK: - Scanning

    /// Scans everything the Overview sums again: worktrees, DerivedData, Docker and Simulators, and project
    /// folders when their screen has measured them once.
    public func refresh() async {
        async let worktreeScan: Void = app.refresh()
        async let derivedDataScan: Void = derivedData.refresh()
        async let dockerScan: Void = dockerSimulators.refresh()
        _ = await (worktreeScan, derivedDataScan, dockerScan)
        // Project folders are heavy to measure: again only once their screen has measured them.
        if projects.report != nil { await projects.refresh() }
    }

    /// The first look, when the window opens: DerivedData, Docker and Simulators are scanned once (the
    /// worktree scan starts with the app).
    public func loadIfNeeded() async {
        async let derivedDataScan: Void = derivedData.loadIfNeeded()
        async let dockerScan: Void = dockerSimulators.loadIfNeeded()
        _ = await (derivedDataScan, dockerScan)
    }
}
