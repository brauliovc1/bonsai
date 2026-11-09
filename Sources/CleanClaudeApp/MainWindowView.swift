import CleanAppModel
import SwiftUI

/// The main window: the sidebar in two groups ("Clean up" with what each screen can free as a badge, "History
/// and info") and the selected screen. It opens on the Overview and measures what the total needs once.
struct MainWindowView: View {
    let models: ScreenModels
    @Bindable private var navigation: NavigationModel

    init(models: ScreenModels) {
        self.models = models
        navigation = models.navigation
    }

    var body: some View {
        NavigationSplitView {
            AppSidebar(summary: models.overview.summary, selection: $navigation.section)
                .navigationSplitViewColumnWidth(min: 214, ideal: 240)
        } detail: {
            detail
        }
        .frame(minWidth: 860, minHeight: 480)
        .modifier(DockIconWhileOpen())
        .task { await models.overview.loadIfNeeded() }
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.section ?? .overview {
        case .overview: OverviewView(model: models.overview, settings: models.settings)
        case .worktrees: WorktreesView(model: models.worktrees)
        case .projects: ProjectsView(model: models.projects, navigation: models.navigation)
        case .caches: CachesView(model: models.caches)
        case .dockerSimulators: DockerSimulatorsView(model: models.dockerSimulators)
        case .derivedData: DerivedDataView(model: models.derivedData)
        case .recentlyRemoved: RecentlyRemovedView(model: models.removals)
        case .claudeUsage: ClaudeUsageView(model: models.claudeUsage)
        }
    }
}

/// The sidebar: "Clean up" with what each screen can free as a trailing badge, then "History and info".
struct AppSidebar: View {
    let summary: ReclaimSummary
    @Binding var selection: SidebarSection?

    var body: some View {
        List(selection: $selection) {
            ForEach(SidebarSection.Group.allCases) { group in
                Section(group.title) {
                    ForEach(group.sections) { section in
                        SidebarRow(section: section, badge: section.badge(in: summary))
                            .tag(section)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

/// One sidebar item: its icon in a fixed-width column so every title lines up, and what the screen can free as
/// a trailing badge.
private struct SidebarRow: View {
    let section: SidebarSection
    let badge: String?

    var body: some View {
        Label {
            Text(section.title)
        } icon: {
            Image(systemName: section.systemImage)
                .font(.system(size: 13))
                .frame(width: 20, height: 18)
        }
        .badge(badge.map { Text($0).monospacedDigit() })
    }
}
