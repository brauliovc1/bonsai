import AppKit
import CleanAppModel
import SwiftUI

/// The menu-bar window: free space, what can be reclaimed now, the last scan, and the app's commands.
struct MenuContentView: View {
    let app: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DiskSummaryView(disk: app.disk)
            Divider()
            HStack {
                Text("Reclaimable now")
                Spacer()
                Text(app.scan == nil ? "–" : DisplayText.bytes(app.reclaimableBytes))
                    .monospacedDigit()
                    .fontWeight(.semibold)
            }
            .help("Estimated size of the SAFE and AUTO-READY worktrees")
            ScanTimeText(app: app)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let problem = app.problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                MenuButton(title: "Refresh", systemImage: "arrow.clockwise") { app.requestRefresh() }
                    .disabled(app.isScanning)
                MenuButton(title: "Open \(AppInfo.name)", systemImage: "macwindow") { openMainWindow() }
                SettingsLink {
                    Label("Settings…", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // The app has no Dock icon until a window opens, so bring the Settings window forward.
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
                MenuButton(title: "Quit \(AppInfo.name)", systemImage: "power") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 290)
    }

    private func openMainWindow() {
        openWindow(id: AppInfo.mainWindowID)
        NSApp.activate()
    }
}

/// A full-width, menu-like row.
private struct MenuButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
                .background(hovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
