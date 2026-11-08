import AppKit
import CleanAppModel
import SwiftUI

/// The menu-bar item: the drive symbol (a warning triangle below the low-space warning) and the free space.
struct MenuBarLabel: View {
    let model: MenuBarModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: model.symbolName)
            Text(model.freeSpaceText)
                .monospacedDigit()
        }
        .help(model.helpText)
        // The label lives as long as the app, so a notification click can open the main window through it.
        .onAppear { WindowOpener.shared.openWindow = openWindow }
    }
}

/// Opens the main window from outside a view (a notification click).
@MainActor
final class WindowOpener {
    static let shared = WindowOpener()

    var openWindow: OpenWindowAction?

    func openMainWindow() {
        openWindow?(id: AppInfo.mainWindowID)
        NSApp.activate()
    }
}
