import Foundation
import Observation

/// Launch at login, in the Auto mode tab (auto mode needs the app running). Errors are shown, never thrown.
@MainActor
@Observable
public final class LaunchAtLoginModel {
    let service: any LoginItemService
    public private(set) var status: LoginItemStatus
    public private(set) var error: String?

    public init(service: any LoginItemService) {
        self.service = service
        status = service.status
    }

    /// The toggle: on when registered, also while it waits for approval.
    public var isOn: Bool { status == .enabled || status == .requiresApproval }
    /// Show the button that opens Login Items in System Settings.
    public var needsApproval: Bool { status == .requiresApproval }

    public var statusText: String {
        switch status {
        case .enabled: "Opens at login."
        case .notRegistered: "Doesn't open at login, so auto mode only runs after you open it."
        case .requiresApproval: "Waiting for your OK in System Settings › General › Login Items."
        case .notFound: "This copy can't open at login. Move it to /Applications and open it from there."
        }
    }

    public func refresh() {
        status = service.status
    }

    public func setEnabled(_ enabled: Bool) {
        guard enabled != isOn else { return refresh() }
        do {
            if enabled { try service.register() } else { try service.unregister() }
            error = nil
        } catch {
            self.error = (enabled ? "Couldn't turn on launch at login: " : "Couldn't turn off launch at login: ")
                + error.localizedDescription
        }
        refresh()
    }

    public func openSystemSettings() {
        service.openSystemSettingsLoginItems()
    }
}
