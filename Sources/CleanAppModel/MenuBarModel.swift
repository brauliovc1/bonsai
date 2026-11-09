import CleanCore
import Foundation
import Observation

/// The menu-bar label: the bonsai glyph and a bar showing how full the disk is (orange below the low-space
/// warning, red under half of it), the exact numbers in the tooltip and the accessibility label, and at most
/// one low-space notification a day (the date is kept in `settings.json`).
@MainActor
@Observable
public final class MenuBarModel {
    public static let refreshInterval: Duration = .seconds(5 * 60)
    /// At most one low-space notification per this many seconds.
    public static let noticeInterval: TimeInterval = 86_400

    /// How the bar is drawn.
    public enum Level: Sendable, Equatable {
        /// Free space not known yet: an empty bar.
        case unknown
        case normal
        /// Free below the low-space warning: orange.
        case low
        /// Free below half the warning: red.
        case veryLow
    }

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

    /// The bar's fill: the part of the disk in use, 0...1; 0 when unknown.
    public var fillFraction: Double { min(max(app.disk.usedFraction ?? 0, 0), 1) }

    /// Low and very low need only the free space; normal needs the disk's size too (to fill the bar).
    public var level: Level {
        let free = app.disk.freeBytes
        guard free != nil else { return .unknown }
        let warning = app.settings.lowSpaceWarningGB
        if FreeSpaceText.isVeryLow(free, warningGB: warning) { return .veryLow }
        if FreeSpaceText.isLow(free, warningGB: warning) { return .low }
        return app.disk.usedFraction == nil ? .unknown : .normal
    }

    /// "Bonsai: 23 GB free of 460 GB"; read by VoiceOver for the menu-bar item.
    public var accessibilityText: String {
        guard app.disk.freeBytes != nil else { return "\(appName): free space unknown" }
        return "\(appName): \(freeSpaceText) free of \(FreeSpaceText.label(app.disk.totalBytes))"
    }

    /// The tooltip: the accessibility text, and the warning when space is low.
    public var helpText: String {
        guard isLow else { return accessibilityText }
        return "\(accessibilityText), below your \(app.settings.lowSpaceWarningGB) GB warning"
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
