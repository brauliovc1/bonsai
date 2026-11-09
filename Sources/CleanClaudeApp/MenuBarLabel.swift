import AppKit
import CleanAppModel
import SwiftUI

/// The menu-bar item: the bonsai glyph and the disk-fullness bar (`MenuBarImage`). The numbers are in the
/// tooltip, the accessibility label and the menu window.
struct MenuBarLabel: View {
    let model: MenuBarModel
    @Environment(\.openWindow) private var openWindow
    /// Read so a change of appearance draws the image again.
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: MenuBarImage.make(
            fraction: model.fillFraction, level: model.level, description: model.accessibilityText
        ))
        .accessibilityLabel(model.accessibilityText)
        .help(model.helpText)
        .id(colorScheme)
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
