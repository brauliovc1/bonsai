import CleanAppModel
import CleanCore
import SwiftUI

/// The menu-bar app: a menu-bar window with the disk summary, the main window (it opens on the Overview),
/// and the Settings window. No Dock icon (LSUIElement) except while the main window is open.
@main
struct CleanClaudeApp: App {
    @State private var models: ScreenModels

    init() {
        let app = AppModel(environment: .live())
        _models = State(initialValue: ScreenModels(app: app))
        app.requestRefresh()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(app: models.app)
        } label: {
            Image(systemName: "internaldrive")
        }
        .menuBarExtraStyle(.window)

        Window(AppInfo.name, id: AppInfo.mainWindowID) {
            MainWindowView(models: models)
        }
        .defaultSize(width: 1040, height: 640)

        Settings {
            SettingsView(model: models.settings)
        }
    }
}

enum AppInfo {
    /// From Info.plist, so renaming the app (PLAN D1) needs no code change. "Clean Claude" when run
    /// outside the bundle (`swift run`).
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Clean Claude"
    static let mainWindowID = "main"
}
