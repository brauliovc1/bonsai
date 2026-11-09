/// One card the Overview can show (PLAN §8.3), made of one or more parts of the "can free" total. Xcode puts
/// orphaned DerivedData and unavailable simulators together.
public enum OverviewCategory: String, CaseIterable, Identifiable, Sendable {
    case worktrees
    case projectFolders
    case toolCaches
    case docker
    case xcode

    public var id: String { rawValue }

    public var parts: [ReclaimSummary.Part] {
        switch self {
        case .worktrees: [.worktrees]
        case .projectFolders: [.projectFolders]
        case .toolCaches: [.toolCaches]
        case .docker: [.docker]
        case .xcode: [.derivedData, .simulators]
        }
    }

    public var title: String {
        switch self {
        case .worktrees: "Worktrees"
        case .projectFolders: "Project folders"
        case .toolCaches: "Tool caches"
        case .docker: "Docker"
        case .xcode: "Xcode"
        }
    }

    /// The SF Symbol of the screen it opens.
    public var systemImage: String {
        switch self {
        case .worktrees: SidebarSection.worktrees.systemImage
        case .projectFolders: SidebarSection.projects.systemImage
        case .toolCaches: SidebarSection.caches.systemImage
        case .docker: SidebarSection.dockerSimulators.systemImage
        case .xcode: SidebarSection.derivedData.systemImage
        }
    }
}
