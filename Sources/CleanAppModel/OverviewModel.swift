import CleanCore
import Foundation
import Observation

/// The Overview (PLAN §8.3): free space and what Bonsai can free (the one total, `ReclaimSummary`), the bar, a card
/// for each category with something to free (largest first) whose button opens its screen already filtered to
/// what the card counted, one line for the empty ones, and the auto clean row. Every number comes from the other
/// screens' models; nothing is measured again here.
@MainActor
@Observable
public final class OverviewModel {
    public let app: AppModel
    public let worktrees: WorktreesModel
    public let projects: ProjectsModel
    public let derivedData: DerivedDataModel
    public let dockerSimulators: DockerSimulatorsModel
    public let caches: CachesModel
    public let downloads: DownloadsTrashModel
    public let autoMode: AutoModeModel
    public let navigation: NavigationModel
    /// Render seam: a summary to show instead of the models' (the off-screen renders use it for a full disk).
    var summaryOverride: ReclaimSummary?

    public init(
        app: AppModel,
        worktrees: WorktreesModel,
        projects: ProjectsModel,
        derivedData: DerivedDataModel,
        dockerSimulators: DockerSimulatorsModel,
        caches: CachesModel,
        downloads: DownloadsTrashModel? = nil,
        autoMode: AutoModeModel,
        navigation: NavigationModel
    ) {
        self.app = app
        self.worktrees = worktrees
        self.projects = projects
        self.derivedData = derivedData
        self.dockerSimulators = dockerSimulators
        self.caches = caches
        self.downloads = downloads ?? DownloadsTrashModel(app: app)
        self.autoMode = autoMode
        self.navigation = navigation
    }

    public var disk: DiskSpaceModel { app.disk }

    /// The one total, as the screens' models have it now.
    public var summary: ReclaimSummary {
        summaryOverride
            ?? ReclaimSummary(app: app, projects: projects, caches: caches, derivedData: derivedData, dockerSimulators: dockerSimulators, downloads: downloads)
    }

    /// True while anything the Overview sums is being scanned.
    public var isRefreshing: Bool {
        app.isScanning || derivedData.isScanning || dockerSimulators.isScanning || projects.isScanning
            || caches.isScanning || downloads.isScanning
    }

    // MARK: - Headline and bar

    /// "21.9 GB free of 460 GB".
    public var headline: String {
        guard let free = disk.freeBytes else { return "Free space unknown" }
        guard let total = disk.totalBytes else { return "\(DisplayText.bytes(free)) free" }
        return "\(DisplayText.bytes(free)) free of \(FreeSpaceText.label(total))"
    }

    /// "Bonsai can free about 140.2 GB"; "Nothing to clean right now" when every part is known and empty.
    public var canFreeText: String {
        let summary = summary
        if summary.totalBytes > 0 { return "Bonsai can free about \(DisplayText.bytes(summary.totalBytes))" }
        return summary.pendingParts.isEmpty ? "Nothing to clean right now" : "Looking for space to free…"
    }

    /// The headline's right side is green only when there is something to free.
    public var canFreeSomething: Bool { summary.totalBytes > 0 }

    /// How the bar and the headline are colored: the menu bar's rule.
    public var level: MenuBarModel.Level {
        MenuBarModel.level(of: disk, warningGB: app.settings.lowSpaceWarningGB)
    }

    public var space: SpaceBreakdown? {
        SpaceBreakdown(free: disk.freeBytes, total: disk.totalBytes, canFree: summary.totalBytes)
    }

    // MARK: - Cards

    /// The categories with something to free, largest first.
    public var cards: [OverviewCard] {
        let summary = summary
        return OverviewCategory.allCases
            .compactMap { card($0, in: summary) }
            .sorted { $0.bytes > $1.bytes }
    }

    /// The card for one category; nil when it has nothing to free.
    public func card(_ category: OverviewCategory) -> OverviewCard? {
        card(category, in: summary)
    }

    private func card(_ category: OverviewCategory, in summary: ReclaimSummary) -> OverviewCard? {
        let bytes = summary.bytes(category.parts)
        guard bytes > 0 else { return nil }
        return OverviewCard(category: category, bytes: bytes, detail: detail(category, summary))
    }

    private func detail(_ category: OverviewCategory, _ summary: ReclaimSummary) -> String {
        switch category {
        case .worktrees:
            let count = summary.count(.worktrees)
            return "\(DisplayText.worktrees(count)) you can remove; \(count == 1 ? "its branch is" : "branches are") kept"
        case .projectFolders:
            let count = summary.count(.projectFolders)
            return "Dependency and build folders of \(DisplayText.projects(count)) idle \(projects.threshold)+ days"
        case .toolCaches:
            let count = summary.count(.toolCaches)
            return "\(count) \(count == 1 ? "cache" : "caches") the tools download again when needed"
        case .dockerSimulators:
            var parts: [String] = []
            let devices = summary.count(.simulators)
            if summary.bytes(.docker) > 0 { parts.append("Docker's stopped containers, unused images and build cache") }
            if summary.bytes(.simulators) > 0 { parts.append("\(devices) unavailable \(devices == 1 ? "simulator" : "simulators")") }
            return parts.joined(separator: " and ")
        case .derivedData:
            return "\(DisplayText.folders(summary.count(.derivedData))) of deleted projects' DerivedData"
        case .downloads:
            let count = summary.count(.downloads)
            return "\(count) old \(count == 1 ? "installer or archive" : "installers and archives") to move to Trash; empty Trash to free the space"
        }
    }

    // MARK: - Lines under the cards

    /// "Nothing to clean in Tool caches or Xcode DerivedData.": the screens whose parts are all measured and empty;
    /// nil when there is none (a part not measured, or not counted, is not "nothing").
    public var nothingText: String? {
        let summary = summary
        let empty = OverviewCategory.allCases.filter { category in category.parts.allSatisfy(summary.emptyParts.contains) }
        guard !empty.isEmpty else { return nil }
        return "Nothing to clean in \(OverviewCategory.names(empty))."
    }

    /// Why some parts aren't counted ("Docker isn't running, so its space isn't counted."); nil when all are.
    public var notCountedText: String? {
        let reasons = summary.unavailable.map(\.reason)
        return reasons.isEmpty ? nil : reasons.joined(separator: " ")
    }

    /// "Measuring Project folders…" while a screen's parts aren't known yet; nil once they all are.
    public var measuringText: String? {
        let pending = summary.pendingParts
        let screens = OverviewCategory.allCases.filter { $0.parts.contains(where: pending.contains) }
        guard !screens.isEmpty else { return nil }
        return "Measuring \(screens.map(\.title).joined(separator: ", "))…"
    }

    /// The auto clean row.
    public var autoClean: AutoCleanLine { AutoCleanLine(autoMode: autoMode) }

    // MARK: - Opening a screen

    /// Opens the card's screen showing what the card counted: Worktrees on "Can remove", Project folders on
    /// "Ready to clean", Tool caches with the ready ones selected, Xcode DerivedData with the orphans selected,
    /// Docker & Simulators as it is (one prune and one delete, each for everything it counts).
    public func open(_ category: OverviewCategory) {
        switch category {
        case .worktrees:
            worktrees.showRemovable()
            navigation.show(.worktrees)
        case .projectFolders:
            projects.showReclaimable()
            navigation.show(.projects)
        case .toolCaches:
            caches.selectAllReady()
            navigation.show(.caches)
        case .dockerSimulators:
            navigation.show(.dockerSimulators)
        case .derivedData:
            derivedData.selection = derivedData.selectableIDs
            navigation.show(.derivedData)
        case .downloads:
            downloads.selectAllReady()
            navigation.show(.downloads)
        }
    }

    // MARK: - Scanning

    /// Scans everything the total sums again: worktrees, DerivedData, Docker and Simulators and the tool caches,
    /// then the project folders (they read the worktree scan).
    public func refresh() async {
        async let worktreeScan: Void = app.refresh()
        async let derivedDataScan: Void = derivedData.refresh()
        async let dockerScan: Void = dockerSimulators.refresh()
        async let cachesScan: Void = caches.refresh()
        async let downloadsScan: Void = downloads.refresh()
        _ = await (worktreeScan, derivedDataScan, dockerScan, cachesScan, downloadsScan)
        await projects.refresh()
    }

    /// The first look, when the main window or the menu window opens: everything the total sums that hasn't been
    /// measured yet (the worktree scan starts with the app). Project folders are the slow part; they show
    /// "Measuring…" until done.
    public func loadIfNeeded() async {
        async let derivedDataScan: Void = derivedData.loadIfNeeded()
        async let dockerScan: Void = dockerSimulators.loadIfNeeded()
        async let cachesScan: Void = caches.loadIfNeeded()
        async let projectsScan: Void = projects.loadIfNeeded()
        async let downloadsScan: Void = downloads.loadIfNeeded()
        _ = await (derivedDataScan, dockerScan, cachesScan, projectsScan, downloadsScan)
    }
}
