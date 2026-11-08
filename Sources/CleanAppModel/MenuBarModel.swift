import CleanCore
import Foundation
import Observation

/// The menu-bar label: free space next to the drive symbol, a warning triangle below the low-space
/// warning, and at most one low-space notification a day (the date is kept in `settings.json`).
@MainActor
@Observable
public final class MenuBarModel {
    public static let refreshInterval: Duration = .seconds(5 * 60)
    public static let normalSymbol = "internaldrive"
    public static let lowSymbol = "exclamationmark.triangle"
    /// At most one low-space notification per this many seconds.
    public static let noticeInterval: TimeInterval = 86_400

    public let app: AppModel
    let notifier: any Notifier
    let appName: String
    private var refreshTask: Task<Void, Never>?
    /// The last low-space notification this app posted, in case its date could not be saved.
    private var lastNotice: Date?

    public init(app: AppModel, notifier: any Notifier = SilentNotifier(), appName: String = "Bonsai") {
        self.app = app
        self.notifier = notifier
        self.appName = appName
    }

    public var freeSpaceText: String { FreeSpaceText.label(app.disk.freeBytes) }
    public var isLow: Bool { FreeSpaceText.isLow(app.disk.freeBytes, warningGB: app.settings.lowSpaceWarningGB) }
    public var symbolName: String { isLow ? Self.lowSymbol : Self.normalSymbol }

    public var helpText: String {
        let volume = app.disk.volumeName.map { " on \($0)" } ?? ""
        let warning = isLow ? " (below your \(app.settings.lowSpaceWarningGB) GB warning)" : ""
        return "\(freeSpaceText) free\(volume)\(warning)"
    }

    /// Measures the free space again and warns when it is low.
    public func refresh() async {
        if app.disk.folder == nil { app.disk.point(at: app.environment.homeDirectory) }
        app.disk.refresh()
        await checkLowSpace()
    }

    /// Refreshes now and every five minutes until `stopRefreshing()`.
    public func startRefreshing() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await refresh()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
    }

    public func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Posts the low-space notification when space is low and none was posted in the last day. The date is
    /// saved only when a notification was really shown (notifications not allowed = nothing written, also no
    /// settings.json on a fresh install). Unreadable settings = no notification.
    public func checkLowSpace() async {
        guard isLow, let free = app.disk.freeBytes else { return }
        let now = app.environment.now()
        guard let settings = try? SettingsEditor.current(app) else { return }
        for last in [settings.lowSpaceNotifiedAt, lastNotice].compactMap({ $0 })
        where last <= now && now.timeIntervalSince(last) < Self.noticeInterval {
            return
        }
        let posted = await notifier.post(.lowSpace(
            freeBytes: free, warningGB: settings.lowSpaceWarningGB, volumeName: app.disk.volumeName, appName: appName
        ))
        guard posted else { return }
        lastNotice = now
        _ = try? SettingsEditor.update(app) { $0.lowSpaceNotifiedAt = now }
    }
}
