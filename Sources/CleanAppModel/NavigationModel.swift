import Observation

/// Which sidebar screen the main window shows. The window opens on the Overview; its rows jump elsewhere
/// through `show(_:)`.
@MainActor
@Observable
public final class NavigationModel {
    public var section: SidebarSection?

    public init(section: SidebarSection? = .overview) {
        self.section = section
    }

    public func show(_ section: SidebarSection) {
        self.section = section
    }
}
