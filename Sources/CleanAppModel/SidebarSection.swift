/// The main window's sidebar, in order. The one list of screens: a new screen is a case here, a model, a
/// view, and a case in `MainWindowView.detail`. It lives in the model target so the Overview's jump buttons
/// can be tested without a window.
public enum SidebarSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case worktrees
    case derivedData
    case dockerSimulators
    case caches
    case claudeUsage
    case recentlyRemoved

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: "Overview"
        case .worktrees: "Worktrees"
        case .derivedData: "Xcode DerivedData"
        case .dockerSimulators: "Docker & Simulators"
        case .caches: "Tool caches"
        case .claudeUsage: "Claude usage"
        case .recentlyRemoved: "Recently removed"
        }
    }

    /// An SF Symbol name.
    public var systemImage: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"
        case .worktrees: "folder.badge.gearshape"
        case .derivedData: "hammer"
        case .dockerSimulators: "shippingbox"
        case .caches: "archivebox"
        case .claudeUsage: "sparkles"
        case .recentlyRemoved: "clock.arrow.circlepath"
        }
    }
}
