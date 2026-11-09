import CleanAppModel
import SwiftUI

/// The main window: the sidebar sections and the selected screen. It opens on the Overview.
struct MainWindowView: View {
    let models: ScreenModels
    @Bindable private var navigation: NavigationModel

    init(models: ScreenModels) {
        self.models = models
        navigation = models.navigation
    }

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $navigation.section) { section in
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
        switch navigation.section ?? .overview {
        case .overview: OverviewView(model: models.overview)
        case .worktrees: WorktreesView(model: models.worktrees)
        case .projects: ProjectsView(model: models.projects, navigation: models.navigation)
        case .derivedData: DerivedDataView(model: models.derivedData)
        case .dockerSimulators: DockerSimulatorsView(model: models.dockerSimulators)
        case .caches: CachesView(model: models.caches)
        case .claudeUsage: ClaudeUsageView(model: models.claudeUsage)
        case .recentlyRemoved: RecentlyRemovedView(model: models.removals)
        }
    }
}
