import CleanCore
import Foundation

/// Every screen's model, built from one `AppModel` the way the app wires them (and the tests and the
/// off-screen renders do too).
@MainActor
public final class ScreenModels {
    public let app: AppModel
    public let navigation: NavigationModel
    public let worktrees: WorktreesModel
    public let removals: RemovalsModel
    public let derivedData: DerivedDataModel
    public let dockerSimulators: DockerSimulatorsModel
    public let claudeUsage: ClaudeUsageModel
    public let overview: OverviewModel
    public let settings: SettingsModel

    /// `runner`: how docker, xcrun and `defaults` are run; tests pass a scripted one.
    public init(app: AppModel, runner: CommandRunner = .live, navigation: NavigationModel = NavigationModel()) {
        self.app = app
        self.navigation = navigation
        worktrees = WorktreesModel(app: app)
        removals = RemovalsModel(app: app)
        derivedData = DerivedDataModel(app: app, runner: runner)
        dockerSimulators = DockerSimulatorsModel(app: app, runner: runner)
        claudeUsage = ClaudeUsageModel(app: app)
        settings = SettingsModel(app: app)
        overview = OverviewModel(
            app: app,
            worktrees: worktrees,
            derivedData: derivedData,
            dockerSimulators: dockerSimulators,
            navigation: navigation
        )
    }
}
