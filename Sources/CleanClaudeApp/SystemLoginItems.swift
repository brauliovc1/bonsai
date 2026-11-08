import CleanAppModel
import ServiceManagement

/// Launch at login through SMAppService.mainApp. macOS only accepts it for an app it can find as a bundle
/// (in practice: in /Applications).
@MainActor
final class SystemLoginItems: LoginItemService {
    private let service = SMAppService.mainApp

    var status: LoginItemStatus {
        switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered: .notRegistered
        case .notFound: .notFound
        @unknown default: .notFound
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
