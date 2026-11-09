import CleanCore
import Foundation

extension ReclaimSummary {
    /// The summary from the screens' models as they are now: their own numbers, never measured again here.
    @MainActor
    public init(
        app: AppModel,
        projects: ProjectsModel,
        caches: CachesModel,
        derivedData: DerivedDataModel,
        dockerSimulators: DockerSimulatorsModel
    ) {
        self.init([
            .worktrees: Self.worktrees(app),
            .projectFolders: Self.projectFolders(projects),
            .toolCaches: Self.toolCaches(caches),
            .docker: Self.docker(dockerSimulators),
            .derivedData: Self.derivedData(derivedData),
            .simulators: Self.simulators(dockerSimulators),
        ])
    }

    @MainActor
    private static func worktrees(_ app: AppModel) -> State {
        guard app.scan != nil else {
            if app.isScanning { return .measuring }
            return app.problem.map(State.unavailable) ?? .notMeasured
        }
        let removable = app.removableAssessments
        return .measured(bytes: removable.compactMap(\.estimatedBytes).reduce(0, +), count: removable.count)
    }

    @MainActor
    private static func projectFolders(_ projects: ProjectsModel) -> State {
        guard projects.report != nil else { return projects.isScanning ? .measuring : .notMeasured }
        let total = projects.reclaimableTotal
        return .measured(bytes: total.bytes, count: total.count)
    }

    @MainActor
    private static func toolCaches(_ caches: CachesModel) -> State {
        guard caches.report != nil else { return caches.isScanning ? .measuring : .notMeasured }
        return .measured(bytes: caches.readyBytes, count: caches.readyRows.count)
    }

    @MainActor
    private static func docker(_ model: DockerSimulatorsModel) -> State {
        switch model.dockerStatus {
        case .unknown:
            return model.isScanning ? .measuring : .notMeasured
        case .notInstalled:
            return .measured(bytes: 0, count: 0)
        case .notRunning:
            return .unavailable("Docker isn't running, so its space isn't counted.")
        case .running:
            if let failure = model.dockerReadFailure { return .unavailable("Couldn't read Docker's space: \(failure).") }
            return .measured(bytes: model.dockerReclaimableBytes ?? 0, count: 0)
        }
    }

    @MainActor
    private static func derivedData(_ model: DerivedDataModel) -> State {
        guard model.report != nil else { return model.isScanning ? .measuring : .notMeasured }
        if let refusal = model.refusal { return .unavailable("Xcode DerivedData isn't counted: \(refusal)") }
        return .measured(bytes: model.orphanBytes, count: model.orphanRows.count)
    }

    @MainActor
    private static func simulators(_ model: DockerSimulatorsModel) -> State {
        guard model.simulators != nil else { return model.isScanning ? .measuring : .notMeasured }
        if model.noXcode { return .measured(bytes: 0, count: 0) }
        if let failure = model.deviceListFailure { return .unavailable("Couldn't read the simulators: \(failure).") }
        return .measured(bytes: model.unavailableBytes ?? 0, count: model.unavailableDevices.count)
    }
}
