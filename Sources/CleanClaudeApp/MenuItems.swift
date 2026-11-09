import AppKit
import SwiftUI

/// A menu-like row: the icon in a fixed-width column so the titles line up, and the keyboard shortcut on
/// the right in a quieter colour, as in a macOS menu.
struct MenuRowLabel: View {
    let title: String
    let systemImage: String
    var shortcut: String?
    var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
            Spacer(minLength: 8)
            if let shortcut {
                Text(shortcut).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(hovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 5))
    }
}

/// A full-width, menu-like button.
struct MenuButton: View {
    let title: String
    let systemImage: String
    var shortcut: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            MenuRowLabel(title: title, systemImage: systemImage, shortcut: shortcut, hovering: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// "Settings…" as a menu-like row.
struct MenuSettingsRow: View {
    @State private var hovering = false

    var body: some View {
        SettingsLink {
            MenuRowLabel(title: "Settings…", systemImage: "gearshape", hovering: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        // The app has no Dock icon until a window opens, so bring the Settings window forward.
        .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
    }
}
