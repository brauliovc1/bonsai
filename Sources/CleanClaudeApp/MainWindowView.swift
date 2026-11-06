import CleanAppModel
import SwiftUI

/// The main window: the sidebar sections and the selected screen.
struct MainWindowView: View {
    let app: AppModel
    let worktrees: WorktreesModel
    let removals: RemovalsModel
    @State private var section: SidebarSection? = .worktrees

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $section) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            detail
        }
        .frame(minWidth: 820, minHeight: 440)
        .modifier(DockIconWhileOpen())
    }

    @ViewBuilder
    private var detail: some View {
        switch section ?? .worktrees {
        case .worktrees: WorktreesView(model: worktrees)
        case .recentlyRemoved: RecentlyRemovedView(model: removals)
        }
    }
}
