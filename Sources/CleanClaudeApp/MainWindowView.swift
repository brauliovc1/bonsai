import CleanAppModel
import SwiftUI

/// The main window: the sidebar in two groups ("Clean up" with what each screen can free as a badge, "History
/// and info") and the selected screen. It opens on the Overview and measures what the total needs once.
struct MainWindowView: View {
    let models: ScreenModels
    @Bindable private var navigation: NavigationModel
    @Bindable private var queue: CleanupQueue

    init(models: ScreenModels) {
        self.models = models
        navigation = models.navigation
        queue = models.app.cleanupQueue
    }

    var body: some View {
        NavigationSplitView {
            AppSidebar(summary: models.overview.summary, selection: $navigation.section)
                .navigationSplitViewColumnWidth(min: 214, ideal: 240)
        } detail: {
            VStack(spacing: 0) {
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 8) {
                    if !queue.toasts.isEmpty {
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(queue.toasts) { toast in CleanupToastView(toast: toast, queue: queue) }
                            }
                            .padding(.horizontal, 1)
                        }
                        .frame(height: min(CGFloat(queue.toasts.count) * 76, 152))
                    }
                    CleanupActivityView(queue: queue)
                }
                .padding(queue.hasPending || !queue.toasts.isEmpty ? 12 : 0)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(minWidth: 860, minHeight: 480)
        .modifier(DockIconWhileOpen())
        .onAppear { queue.windowIsVisible = true }
        .onDisappear { queue.windowIsVisible = false }
        .sheet(item: $queue.selectedTask) { task in CleanupTaskSheet(task: task, queue: queue) }
        .task { await models.overview.loadIfNeeded() }
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.section ?? .overview {
        case .compare: CompareView(model: models.compare, navigation: models.navigation, worktrees: models.worktrees)
        case .overview: OverviewView(model: models.overview, settings: models.settings)
        case .worktrees: WorktreesView(model: models.worktrees)
        case .projects: ProjectsView(model: models.projects, navigation: models.navigation)
        case .caches: CachesView(model: models.caches)
        case .downloads: DownloadsTrashView(model: models.downloads)
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
