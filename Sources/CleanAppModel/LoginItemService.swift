import Foundation

/// What macOS says about the app as a login item (SMAppService.Status).
public enum LoginItemStatus: Sendable, Hashable {
    case notRegistered
    case enabled
    /// Registered, waiting for the person to allow it in System Settings › General › Login Items.
    case requiresApproval
    /// This copy of the app can't be a login item (not found by macOS, e.g. not in /Applications).
    case notFound
}

/// Registers the app to open at login. The app's is SMAppService.mainApp; tests use a fake.
@MainActor
public protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    /// Opens System Settings › General › Login Items.
    func openSystemSettingsLoginItems()
}

/// No login item: for runs without an app bundle and for off-screen renders.
@MainActor
public final class UnavailableLoginItems: LoginItemService {
    public init() {}
    public var status: LoginItemStatus { .notFound }
    public func register() throws { throw Unavailable() }
    public func unregister() throws {}
    public func openSystemSettingsLoginItems() {}

    struct Unavailable: LocalizedError {
        var errorDescription: String? { "login items need the app bundle" }
    }
}
