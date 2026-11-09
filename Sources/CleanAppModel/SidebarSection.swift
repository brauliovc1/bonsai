/// The main window's sidebar, in order (PLAN §8.3). The one list of screens: a new screen is a case here, a
/// model, a view, and a case in `MainWindowView.detail`. It lives in the model target so the Overview's buttons
/// and the badges can be tested without a window.
public enum SidebarSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case worktrees
    case projects
    case caches
    case dockerSimulators
    case derivedData
    case recentlyRemoved
    case claudeUsage

    /// The sidebar's two groups.
    public enum Group: String, CaseIterable, Identifiable, Sendable {
        case cleanUp
        case historyAndInfo

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .cleanUp: "Clean up"
            case .historyAndInfo: "History and info"
            }
        }

        /// The group's screens, in sidebar order.
        public var sections: [SidebarSection] { SidebarSection.allCases.filter { $0.group == self } }
    }

    public var id: String { rawValue }

    public var group: Group {
        switch self {
        case .overview, .worktrees, .projects, .caches, .dockerSimulators, .derivedData: .cleanUp
        case .recentlyRemoved, .claudeUsage: .historyAndInfo
        }
    }

    public var title: String {
        switch self {
        case .overview: "Overview"
        case .worktrees: "Worktrees"
        case .projects: "Project folders"
        case .caches: "Tool caches"
        case .dockerSimulators: "Docker & Simulators"
        case .derivedData: "Xcode DerivedData"
        case .recentlyRemoved: "Recently removed"
        case .claudeUsage: "Claude usage"
        }
    }

    /// An SF Symbol name.
    public var systemImage: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"
        case .worktrees: "arrow.triangle.branch"
        case .projects: "folder"
        case .caches: "archivebox"
        case .dockerSimulators: "shippingbox"
        case .derivedData: "hammer"
        case .recentlyRemoved: "clock.arrow.circlepath"
        case .claudeUsage: "sparkles"
        }
    }

    /// The parts of the "can free" total this screen frees; its badge is their sum. None for the Overview (it
    /// shows the whole total) and the history and info screens.
    public var reclaimParts: [ReclaimSummary.Part] {
        switch self {
        case .worktrees: [.worktrees]
        case .projects: [.projectFolders]
        case .caches: [.toolCaches]
        case .dockerSimulators: [.docker, .simulators]
        case .derivedData: [.derivedData]
        case .overview, .recentlyRemoved, .claudeUsage: []
        }
    }

    /// The trailing badge: what this screen can free ("56.5 GB"); nil when that is nothing.
    public func badge(in summary: ReclaimSummary) -> String? {
        let bytes = summary.bytes(reclaimParts)
        return bytes > 0 ? DisplayText.bytes(bytes) : nil
    }
}
