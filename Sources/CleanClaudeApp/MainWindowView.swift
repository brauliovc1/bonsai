import CleanAppModel
import SwiftUI

/// The main window: the sidebar in two groups ("Clean up" with what each screen can free as a badge, "History
/// and info") and the selected screen. It opens on the Overview and measures what the total needs once.
struct MainWindowView: View {
    let models: ScreenModels
    @Bindable private var navigation: NavigationModel
    @Bindable private var queue: CleanupQueue
    @Bindable private var quickClean: QuickCleanModel

    init(models: ScreenModels) {
        self.models = models
        navigation = models.navigation
        queue = models.app.cleanupQueue
        quickClean = models.quickClean
    }

    var body: some View {
        NavigationSplitView {
            AppSidebar(summary: models.overview.summary, selection: $navigation.section)
                .navigationSplitViewColumnWidth(min: 220, ideal: 256)
        } detail: {
            GeometryReader { viewport in
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
                .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
            }
        }
        .frame(minWidth: 860, minHeight: 480)
        .modifier(DockIconWhileOpen())
        .onAppear { queue.windowIsVisible = true }
        .onDisappear { queue.windowIsVisible = false }
        .sheet(item: $queue.selectedTask) { task in CleanupTaskSheet(task: task, queue: queue) }
        .sheet(isPresented: $quickClean.isPresented) {
            QuickCleanSheet(model: quickClean)
        }
        .task { await models.overview.loadIfNeeded() }
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.section ?? .overview {
        case .compare: CompareView(model: models.compare, navigation: models.navigation, worktrees: models.worktrees)
        case .overview:
            OverviewView(model: models.overview, settings: models.settings, quickClean: models.quickClean) {
                models.navigation.openBranchMap()
                Task { await models.compare.openBranchMap() }
            }
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
            ForEach([SidebarSection.Group.cleanUp, .review, .historyAndInfo]) { group in
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
        HStack(spacing: 8) {
            Image(systemName: section.systemImage)
                .font(.system(size: 13))
                .frame(width: 20, height: 18)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Text(section.title).fixedSize()
                    Spacer(minLength: 0)
                    if let badge { Text(badge).font(.caption).foregroundStyle(.secondary).monospacedDigit().fixedSize() }
                }
                Text(section.title).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(section.title + (badge.map { ", " + $0 } ?? ""))
        .help(section.title + (badge.map { " · " + $0 + " available to review" } ?? ""))
    }
}
