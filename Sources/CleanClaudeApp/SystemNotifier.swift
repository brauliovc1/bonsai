import CleanAppModel
import Foundation
import UserNotifications

/// Notifications through UNUserNotificationCenter. Clicking one opens the main window on the screen it
/// names. Without an app bundle (`swift run`) nothing is shown: the center needs one.
@MainActor
final class SystemNotifier: NSObject, Notifier, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter?
    private let open: @MainActor (SidebarSection) -> Void

    /// `open`: shows the main window on a screen (called when a notification is clicked).
    init(open: @escaping @MainActor (SidebarSection) -> Void) {
        center = Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
        self.open = open
        super.init()
        center?.delegate = self
    }

    func requestAuthorization() async -> Bool {
        guard let center else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func post(_ content: NotificationContent) async {
        guard let center else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        let message = UNMutableNotificationContent()
        message.title = content.title
        message.body = content.body
        message.userInfo = ["opens": content.opens.rawValue]
        try? await center.add(UNNotificationRequest(identifier: content.identifier, content: message, trigger: nil))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let section = response.notification.request.content.userInfo["opens"] as? String
        await clicked(section)
    }

    /// Shown also while the app is in front (a menu-bar app often is).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    private func clicked(_ section: String?) {
        open(section.flatMap(SidebarSection.init(rawValue:)) ?? .overview)
    }
}
