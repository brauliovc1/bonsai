import AppKit
import CleanAppModel
import CleanCore
import SwiftUI

/// The menu-bar app: a menu-bar window with the disk summary, the main window (it opens on the Overview),
/// and the Settings window. No Dock icon (LSUIElement) except while the main window is open.
///
/// At launch: the first scan, the free-space label (every five minutes), and auto mode's scheduler (a check
/// now, hourly and a few minutes after a wake; each runs only when auto mode is on and a day has passed).
/// Quitting waits for a removal in progress (AppDelegate).
@main
struct CleanClaudeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var models: ScreenModels

    init() {
        let app = AppModel(environment: .live())
        AppDelegate.app = app
        let navigation = NavigationModel()
        let notifier = SystemNotifier { section in
            navigation.show(section)
            WindowOpener.shared.openMainWindow()
        }
        let hasBundle = Bundle.main.bundleIdentifier != nil
        let models = ScreenModels(
            app: app,
            processes: .live(cursorAppRunning: CursorAppProbe.isRunning),
            navigation: navigation,
            notifier: notifier,
            loginItems: hasBundle ? SystemLoginItems() : nil,
            appName: AppInfo.name
        )
        _models = State(initialValue: models)
        app.requestRefresh()
        models.menuBar.startRefreshing()
        models.autoScheduler.start(
            wakeCenter: NSWorkspace.shared.notificationCenter,
            wakeName: NSWorkspace.didWakeNotification
        )
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(
                app: models.app, autoMode: models.autoMode, menuBar: models.menuBar, navigation: models.navigation
            )
        } label: {
            MenuBarLabel(model: models.menuBar)
        }
        .menuBarExtraStyle(.window)

        Window(AppInfo.name, id: AppInfo.mainWindowID) {
            MainWindowView(models: models)
        }
        .defaultSize(width: 1280, height: 700)

        Settings {
            SettingsView(model: models.settings, autoMode: models.autoMode, launchAtLogin: models.launchAtLogin)
        }
    }
}

enum AppInfo {
    /// From Info.plist, so renaming the app (PLAN D1) needs no code change. "Bonsai" when run
    /// outside the bundle (`swift run`).
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Bonsai"
    static let mainWindowID = "main"
}
