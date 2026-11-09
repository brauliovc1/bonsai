import AppKit
import CleanAppModel
import SwiftUI

/// The menu-bar window: the app's name (and a "Test mode" tag under CLEAN_CLAUDE_SCAN_ROOTS) with Refresh,
/// free space, what can be reclaimed now (a row that opens Worktrees), one status line for the last scan and
/// auto mode, and the app's commands.
struct MenuContentView: View {
    let app: AppModel
    let autoMode: AutoModeModel
    let menuBar: MenuBarModel
    let navigation: NavigationModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuHeader(app: app)
                .padding(.bottom, 12)
            DiskSummaryView(disk: app.disk, level: menuBar.level)
            ReclaimRow(bytes: app.scan == nil ? nil : app.reclaimableBytes) {
                navigation.show(.worktrees)
                openMainWindow()
            }
            .padding(.top, 14)
            statusLine
                .padding(.top, 8)
                .padding(.horizontal, 2)
            if app.isQuitting && app.isCleaningUp {
                Label("Finishing the current removal…", systemImage: "hourglass")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 8)
            }
            if let problem = app.problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            Divider()
                .padding(.top, 10)
                .padding(.bottom, 6)
            VStack(alignment: .leading, spacing: 1) {
                MenuButton(title: "Open \(AppInfo.name)", systemImage: "macwindow", shortcut: "⌘O") { openMainWindow() }
                    .keyboardShortcut("o")
                MenuSettingsRow()
                MenuButton(title: "Quit \(AppInfo.name)", systemImage: "power", shortcut: "⌘Q") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(12)
        .frame(width: 290)
    }

    /// "Scanned 51 minutes ago · Auto mode: off", or what the running scan or auto run is doing.
    private var statusLine: some View {
        let scanning = app.isScanning ? DisplayText.progress(app.progress) : nil
        let lastScan = app.lastScanAt
        let auto = autoMode.isRunning ? "Auto mode is running…" : autoMode.statusText
        return TimelineView(.everyMinute) { _ in
            let scan = scanning
                ?? lastScan.map { "Scanned \($0.formatted(.relative(presentation: .named)))" }
                ?? "Not scanned yet"
            Text("\(scan) · \(auto)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func openMainWindow() {
        openWindow(id: AppInfo.mainWindowID)
        NSApp.activate()
    }
}

/// "Ready to clean  20.2 MB  ›": the estimated size of the SAFE and AUTO-READY worktrees. Clicking it opens
/// the Worktrees screen.
private struct ReclaimRow: View {
    let bytes: Int64?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "scissors")
                    .foregroundStyle(.green)
                    .frame(width: 18)
                Text("Ready to clean")
                Spacer(minLength: 8)
                Text(DisplayText.bytes(bytes))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(Color.primary.opacity(hovering ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Estimated size of the SAFE and AUTO-READY worktrees. Click to open Worktrees.")
    }
}
