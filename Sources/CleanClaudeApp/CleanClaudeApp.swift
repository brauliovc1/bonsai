import CleanAppModel
import CleanCore
import SwiftUI

/// The menu-bar app: a menu-bar window with the disk summary, the main window, and an empty Settings
/// scene (P6 fills it). No Dock icon (LSUIElement) except while the main window is open.
@main
struct CleanClaudeApp: App {
    @State private var app: AppModel
    @State private var worktrees: WorktreesModel
    @State private var removals: RemovalsModel

    init() {
        let app = AppModel(environment: .live())
        _app = State(initialValue: app)
        _worktrees = State(initialValue: WorktreesModel(app: app))
        _removals = State(initialValue: RemovalsModel(app: app))
        app.requestRefresh()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(app: app)
        } label: {
            Image(systemName: "internaldrive")
        }
        .menuBarExtraStyle(.window)

        Window(AppInfo.name, id: AppInfo.mainWindowID) {
            MainWindowView(app: app, worktrees: worktrees, removals: removals)
        }
        .defaultSize(width: 1040, height: 640)

        Settings {
            EmptyView()
        }
    }
}

enum AppInfo {
    /// From Info.plist, so renaming the app (PLAN D1) needs no code change. "Clean Claude" when run
    /// outside the bundle (`swift run`).
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Clean Claude"
    static let mainWindowID = "main"
}
