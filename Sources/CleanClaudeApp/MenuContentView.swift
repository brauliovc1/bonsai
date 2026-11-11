import AppKit
import CleanAppModel
import SwiftUI

/// The menu-bar window: the app's name (and a "Test mode" tag under BONSAI_SCAN_ROOTS) with Refresh,
/// free space, what Bonsai can free (the Overview's one total; its tooltip lists the parts and a click opens the
/// Overview), one status line for the last scan and auto mode, and the app's commands.
struct MenuContentView: View {
    let app: AppModel
    let autoMode: AutoModeModel
    let menuBar: MenuBarModel
    let overview: OverviewModel
    let navigation: NavigationModel
    var quickClean: QuickCleanModel? = nil
    var compare: CompareModel? = nil
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuHeader(app: app)
                .padding(.bottom, 12)
            DiskSummaryView(disk: app.disk, level: menuBar.level)
            ReclaimRow(summary: overview.summary) {
                navigation.show(.overview)
                openMainWindow()
            }
            .padding(.top, 14)
            if let quickClean {
                Button {
                    openMainWindow()
                    Task { await quickClean.begin() }
                } label: {
                    Label("Quick clean…", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(quickClean.isPreparing || app.isQuitting)
                .padding(.top, 10)
                .help("Review inactive worktrees, project folders and eligible caches before cleaning")
            }
            CleanupActivityView(queue: app.cleanupQueue, compact: true)
                .padding(.top, app.cleanupQueue.hasPending ? 10 : 0)
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
                if let compare {
                    MenuButton(title: "View branches", systemImage: "point.3.connected.trianglepath.dotted") {
                        navigation.openBranchMap()
                        openMainWindow()
                        Task { await compare.openBranchMap() }
                    }
                    .disabled(app.scan?.worktrees.isEmpty != false)
                    .help(app.scan?.worktrees.isEmpty != false
                        ? "Scan a repository first to view its branches."
                        : "Open the branch timeline, distances and history")
                }
                MenuSettingsRow()
                MenuButton(title: "Quit \(AppInfo.name)", systemImage: "power", shortcut: "⌘Q") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(12)
        .frame(width: 290)
        .task { await overview.loadIfNeeded() }
        .onChange(of: app.cleanupQueue.selectedTask?.id) { _, id in
            if id != nil { openMainWindow() }
        }
    }

    /// "Scanned 51 minutes ago · Auto mode: off", or what the running scan or auto run is doing.
    private var statusLine: some View {
        let scanning = app.isScanning ? DisplayText.progress(app.progress) : nil
        let lastScan = app.lastScanAt
        let auto = autoMode.isRunning ? "Auto clean is running…" : autoMode.statusText
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

/// "Ready to clean  140.2 GB  ›": what Bonsai can free, the same total as the Overview's headline (`ReclaimSummary`);
/// "–" until something has been measured. The tooltip lists the parts; clicking it opens the Overview.
private struct ReclaimRow: View {
    let summary: ReclaimSummary
    let action: () -> Void

    private var bytes: Int64? {
        summary.pendingParts.count == ReclaimSummary.Part.allCases.count ? nil : summary.totalBytes
    }
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
        .help(summary.partsHelp + "\nClick to open the Overview.")
    }
}
