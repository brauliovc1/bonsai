import CleanCore
import Foundation

/// Every screen's model, built from one `AppModel` the way the app wires them (and the tests and the
/// off-screen renders do too).
@MainActor
public final class ScreenModels {
    public let app: AppModel
    public let navigation: NavigationModel
    public let worktrees: WorktreesModel
    public let compare: CompareModel
    public let projects: ProjectsModel
    public let removals: RemovalsModel
    public let derivedData: DerivedDataModel
    public let dockerSimulators: DockerSimulatorsModel
    public let caches: CachesModel
    public let downloads: DownloadsTrashModel
    public let claudeUsage: ClaudeUsageModel
    public let overview: OverviewModel
    public let settings: SettingsModel
    public let autoMode: AutoModeModel
    public let autoScheduler: AutoModeScheduler
    public let launchAtLogin: LaunchAtLoginModel
    public let menuBar: MenuBarModel

    /// `runner`: how docker, xcrun and `defaults` are run; tests pass a scripted one. `processes`: where the
    /// Tool caches screen gets process lists (the app adds its NSWorkspace check for Cursor). `notifier` and
    /// `loginItems`: the app passes UNUserNotificationCenter and SMAppService; the defaults do nothing.
    public init(
        app: AppModel,
        runner: CommandRunner = .live,
        processes: ProcessSource = .live(),
        navigation: NavigationModel = NavigationModel(),
        notifier: (any Notifier)? = nil,
        loginItems: (any LoginItemService)? = nil,
        trashEmptier: any TrashEmptier = UnavailableTrashEmptier(),
        appName: String = "Bonsai"
    ) {
        let notifier = notifier ?? SilentNotifier()
        self.app = app
        self.navigation = navigation
        worktrees = WorktreesModel(app: app)
        compare = CompareModel(app: app)
        worktrees.onCompare = { repo, selection in navigation.openCompare(repo: repo, compare: selection) }
        projects = ProjectsModel(app: app)
        removals = RemovalsModel(app: app)
        derivedData = DerivedDataModel(app: app, runner: runner)
        dockerSimulators = DockerSimulatorsModel(app: app, runner: runner)
        caches = CachesModel(app: app, processes: processes)
        downloads = DownloadsTrashModel(app: app, runner: runner, emptier: trashEmptier)
        claudeUsage = ClaudeUsageModel(app: app)
        settings = SettingsModel(app: app)
        autoMode = AutoModeModel(app: app, notifier: notifier, appName: appName)
        autoScheduler = AutoModeScheduler(model: autoMode)
        launchAtLogin = LaunchAtLoginModel(service: loginItems ?? UnavailableLoginItems())
        let menuBar = MenuBarModel(app: app, notifier: notifier, appName: appName)
        self.menuBar = menuBar
        app.cleanupQueue.notify = { [weak app] task in
            guard let app, !app.isQuitting else { return }
            await notifier.post(NotificationContent(identifier: "cleanup-" + task.id.uuidString, title: appName,
                                                     body: task.summary, opens: .recentlyRemoved))
        }
        autoMode.onRunFinished = { await menuBar.refresh() }
        overview = OverviewModel(
            app: app,
            worktrees: worktrees,
            projects: projects,
            derivedData: derivedData,
            dockerSimulators: dockerSimulators,
            caches: caches,
            downloads: downloads,
            autoMode: autoMode,
            navigation: navigation
        )
    }
}
