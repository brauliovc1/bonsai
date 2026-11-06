import AppKit
import SwiftUI

/// While the view is on screen the app is a regular app (Dock icon, can take focus); when it goes away,
/// back to an accessory app that lives only in the menu bar.
struct DockIconWhileOpen: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate()
            }
            .onDisappear {
                NSApp.setActivationPolicy(.accessory)
            }
    }
}
