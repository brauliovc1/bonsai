/// The main window's sidebar, in order. Later phases add their screens here (Overview, DerivedData,
/// Docker & Simulators, Claude usage) and a case in `MainWindowView.detail`.
enum SidebarSection: String, CaseIterable, Identifiable {
    case worktrees
    case recentlyRemoved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .worktrees: "Worktrees"
        case .recentlyRemoved: "Recently removed"
        }
    }

    var systemImage: String {
        switch self {
        case .worktrees: "folder.badge.gearshape"
        case .recentlyRemoved: "clock.arrow.circlepath"
        }
    }
}
