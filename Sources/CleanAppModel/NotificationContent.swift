import CleanCore
import Foundation

/// One notification: what it says and which screen a click opens. Pure; `Notifier` shows it.
public struct NotificationContent: Sendable, Hashable {
    /// A new notification replaces the one with the same identifier (one per kind).
    public var identifier: String
    public var title: String
    public var body: String
    /// The screen the main window opens on when the notification is clicked.
    public var opens: SidebarSection

    public static let autoRunIdentifier = "auto-run"
    public static let lowSpaceIdentifier = "low-space"

    public init(identifier: String, title: String, body: String, opens: SidebarSection) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.opens = opens
    }

    /// What an auto-mode run reports, or nil when there is nothing to say (nothing planned, nothing kept for
    /// local work, nothing left alone or failed). A report-only run opens the Overview, a normal run
    /// Recently removed.
    public static func autoRun(_ summary: AutoRunSummary, appName: String = "Bonsai") -> NotificationContent? {
        let localWork = summary.notifiedCount > 0
            ? " \(summary.notifiedCount) idle \(summary.notifiedCount == 1 ? "worktree has" : "worktrees have") local work."
            : ""
        if summary.reportOnly {
            guard summary.plannedCount > 0 || summary.notifiedCount > 0 else { return nil }
            let plan = summary.plannedCount > 0
                ? "would remove \(DisplayText.worktrees(summary.plannedCount)), about "
                    + "\(ByteFormatting.string(summary.estimatedBytes))."
                : "nothing to remove."
            let body = "Auto mode (report only): \(plan)\(localWork) Nothing was deleted."
            return NotificationContent(identifier: autoRunIdentifier, title: appName, body: body, opens: .overview)
        }

        let leftAlone = summary.refused.count
        let failed = summary.failures.count
        guard summary.removedCount > 0 || summary.notifiedCount > 0 || leftAlone > 0 || failed > 0 else { return nil }
        var body = summary.removedCount > 0
            ? "Removed \(DisplayText.worktrees(summary.removedCount)), freed \(ByteFormatting.string(summary.freedBytes))."
            : "Auto mode removed nothing."
        body += localWork
        if leftAlone > 0 {
            body += " \(DisplayText.worktrees(leftAlone)) \(leftAlone == 1 ? "was" : "were") left alone after a last check."
        }
        if failed > 0 {
            body += " \(DisplayText.worktrees(failed)) could not be removed."
        }
        return NotificationContent(identifier: autoRunIdentifier, title: appName, body: body, opens: .recentlyRemoved)
    }

    /// Free space fell below the warning. Opens the Overview.
    public static func lowSpace(
        freeBytes: Int64,
        warningGB: Int,
        volumeName: String?,
        appName: String = "Bonsai"
    ) -> NotificationContent {
        let volume = volumeName.map { " on \($0)" } ?? ""
        let body = "Low disk space: \(FreeSpaceText.label(freeBytes)) free\(volume), below your \(warningGB) GB warning. "
            + "Open \(appName) to see what can be removed."
        return NotificationContent(identifier: lowSpaceIdentifier, title: appName, body: body, opens: .overview)
    }
}
