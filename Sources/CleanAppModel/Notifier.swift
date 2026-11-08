import Foundation

/// Shows notifications. The app's is backed by UNUserNotificationCenter; tests use a fake.
@MainActor
public protocol Notifier: AnyObject {
    /// Asks macOS for permission to show notifications (once; later calls just answer). Called when auto
    /// mode is turned on, never at launch.
    func requestAuthorization() async -> Bool
    /// Shows `content`. Returns false when it couldn't be shown (not allowed, no app bundle, an error).
    @discardableResult
    func post(_ content: NotificationContent) async -> Bool
}

/// Shows nothing: for runs without an app bundle and for off-screen renders.
@MainActor
public final class SilentNotifier: Notifier {
    public init() {}
    public func requestAuthorization() async -> Bool { false }
    public func post(_ content: NotificationContent) async -> Bool { false }
}
