import CleanCore
import Foundation
import Observation

/// The Project folders screen (PLAN §4.5): every main checkout and sibling or other worktree of the last scan
/// with light-clean folders, grouped by repo, filtered to the ones idle at least the threshold (or all), with
/// "Select all idle" and "Clean selected…" (`ProjectsModel+Clean`). Claude and Cursor worktrees are only
/// counted. Reading is `ProjectFoldersScanner`; deleting goes only through `LightCleaner` (`LightCleanFlow`).
@MainActor
@Observable
public final class ProjectsModel {
    public enum Filter: String, CaseIterable, Identifiable, Sendable {
        case idle
        case all

        public var id: String { rawValue }
    }

    public let app: AppModel
    @ObservationIgnored private let loop = ScanLoop()

    public private(set) var report: ProjectFoldersReport?
    public private(set) var isScanning = false
    public private(set) var progress: ProjectFoldersScanner.Progress?
    public private(set) var lastScanAt: Date?
    public var filter: Filter = .idle
    public var sortOrder = [KeyPathComparator(\ProjectTableItem.sizeSortKey, order: .reverse)]
    public var selection: Set<ProjectRow.ID> = [] {
        didSet { autoPicked.formIntersection(selection) }
    }
    /// The selected rows "Select all idle" picked (the rest were picked by hand). The sheet doesn't delete one of
    /// these whose idle days, read again, are below the threshold or unknown unless the user ticks it there.
    public internal(set) var autoPicked: Set<ProjectRow.ID> = []
    /// Repos whose group is collapsed (by repo path).
    public internal(set) var collapsedRepos: Set<String> = []
    /// Projects cleaned while a full scan ran: that scan may have looked before the clean, so they are looked
    /// at again when it ends.
    @ObservationIgnored private var cleanedDuringScan: Set<String> = []
    /// Log entries already accounted for (`ProjectsModel+Log`).
    @ObservationIgnored var logSeen = 0
    /// This screen's own clean is finishing: projects the log names are kept for its own rescan.
    @ObservationIgnored var isFinishingClean = false
    @ObservationIgnored var namedByLog: Set<String> = []

    // Clean sheet (ProjectsModel+Clean).
    public var isShowingCleanSheet = false
    public internal(set) var isPreparingClean = false
    public internal(set) var confirmation: ProjectsConfirmation?
    public internal(set) var isCleaning = false
    public internal(set) var cleansDone = 0
    public internal(set) var cleanReport: LightCleanReport?
    @ObservationIgnored var cleanSheetToken = 0

    public init(app: AppModel) {
        self.app = app
        app.whenLogReloads { [weak self] in self?.logReloaded() }
    }

    /// The settings' idle threshold (default 30).
    public var threshold: Int { app.settings.effectiveIdleThresholdDays }

    public func filterTitle(_ filter: Filter) -> String {
        switch filter {
        case .idle: "Idle \(threshold)+ days"
        case .all: "All"
        }
    }

    // MARK: - Rows

    /// Every project of the last projects scan that the last worktree scan still lists.
    public var allRows: [ProjectRow] {
        guard let report else { return [] }
        let listed = Set((app.scan?.worktrees ?? []).map(\.path))
        let home = app.environment.homeDirectory
        return report.projects
            .filter { listed.contains($0.worktree.path) }
            .map { ProjectRow(project: $0, threshold: threshold, home: home) }
    }

    /// The groups the filter shows, sorted; rows inside each group sorted the same way.
    public var groups: [ProjectGroup] {
        let all = allRows
        let shown = all.filter { filter == .all || ($0.idleDays ?? -1) >= threshold }
        let home = app.environment.homeDirectory
        var repos: [String] = []
        var byRepo: [String: [ProjectRow]] = [:]
        for row in shown {
            if byRepo[row.worktree.repoPath] == nil { repos.append(row.worktree.repoPath) }
            byRepo[row.worktree.repoPath, default: []].append(row)
        }
        // Ties by name, then path, so equal keys never swap places between redraws.
        let order = sortOrder + [KeyPathComparator(\ProjectTableItem.nameSortKey), KeyPathComparator(\ProjectTableItem.pathSortKey)]
        let groups = repos.map { repo in
            let rows = (byRepo[repo] ?? []).map(ProjectTableItem.project).sorted(using: order).compactMap(\.row)
            return ProjectGroup(repoPath: repo, rows: rows, totalCount: all.count { $0.worktree.repoPath == repo }, home: home)
        }
        return groups.map(ProjectTableItem.group).sorted(using: order).compactMap {
            if case .group(let group) = $0 { return group }
            return nil
        }
    }

    /// The shown rows in table order.
    public var rows: [ProjectRow] { groups.flatMap(\.rows) }

    /// What the table draws: each group header, then its rows unless it is collapsed.
    public var tableItems: [ProjectTableItem] {
        groups.flatMap { group in
            [ProjectTableItem.group(group)] + (isExpanded(group.repoPath) ? group.rows.map(ProjectTableItem.project) : [])
        }
    }

    public var selectedRows: [ProjectRow] { rows.filter { selection.contains($0.id) } }

    public func isExpanded(_ repoPath: String) -> Bool { !collapsedRepos.contains(repoPath) }

    /// Opens or closes a repo's group; closing it deselects its rows.
    public func toggleExpanded(_ repoPath: String) {
        if collapsedRepos.remove(repoPath) == nil {
            collapsedRepos.insert(repoPath)
            selection.subtract(allRows.filter { $0.worktree.repoPath == repoPath }.map(\.id))
        }
    }

    /// Selects the projects idle at least the threshold, idle known, with nothing stopping a clean (whatever
    /// the filter shows).
    public func selectAllIdle() {
        let ready = allRows.filter(\.isReady)
        for row in ready { collapsedRepos.remove(row.worktree.repoPath) }
        selection = Set(ready.map(\.id))
        autoPicked = selection
    }

    public var canClean: Bool { !selectedRows.isEmpty && !app.isCleaningUp && !isCleaning }

    // MARK: - Totals

    /// What "Select all idle" picks: count and size.
    public var idleTotal: ProjectFoldersReport.Total {
        ProjectFoldersReport.total(allRows.filter(\.isReady).map(\.project))
    }

    public var allTotal: ProjectFoldersReport.Total { ProjectFoldersReport.total(allRows.map(\.project)) }

    /// Claude and Cursor worktrees with light-clean folders, left out of the list.
    public var leftOut: ProjectFoldersReport.Total? {
        guard let total = report?.leftOut, total.count > 0 else { return nil }
        return total
    }

    /// Checkouts the last scan couldn't look at, one sentence each (a stale record, a folder git can't read).
    public var problems: [String] { report?.problems ?? [] }

    /// "3 Claude/Cursor worktrees hold 4.2 GB more; see Worktrees".
    public var leftOutText: String? {
        leftOut.map { total in
            let what = total.count == 1 ? "1 Claude/Cursor worktree holds" : "\(total.count) Claude/Cursor worktrees hold"
            return "\(what) \(DisplayText.bytes(total.bytes)) more; see Worktrees"
        }
    }

    // MARK: - Scanning

    /// Looks at every checkout of the last worktree scan (scanning first when there is none yet), with every
    /// idle clock read now.
    public func refresh() async {
        await loop.run { [self] in
            if app.scan == nil { await app.refresh() }
            guard let scan = app.scan, let git = app.git else { return }
            isScanning = true
            // Cleanups logged from now on are looked at again (`logReloaded`); earlier ones are on disk already.
            logSeen = app.logEntries.count
            report = await scanner(git: git).scan(
                scan.worktrees,
                knownWorktrees: scan.worktrees,
                cwdIndex: await ProcessCwdIndex.capture(lsof: app.environment.tools.lsof),
                log: app.logEntries,
                progress: { [weak self] step in Task { @MainActor in self?.receive(step) } }
            )
            lastScanAt = app.environment.now()
            isScanning = false
            progress = nil
            if !cleanedDuringScan.isEmpty {
                let paths = cleanedDuringScan
                cleanedDuringScan = []
                await lookAgain(at: paths)
            }
            selection.formIntersection(allRows.map(\.id))
        }
    }

    /// Scans the worktrees again, then the projects.
    public func refreshAll() async {
        await app.refresh()
        await refresh()
    }

    /// The first scan, when the screen first appears.
    public func loadIfNeeded() async {
        if report == nil { await refresh() }
    }

    /// Looks again at the projects at `paths` (after a clean), from the worktree scan's current records; when a
    /// full scan runs now, once it ends.
    func rescan(_ paths: Set<String>) async {
        if isScanning {
            cleanedDuringScan.formUnion(paths)
            return
        }
        await lookAgain(at: paths)
        selection.formIntersection(allRows.map(\.id))
    }

    private func lookAgain(at paths: Set<String>) async {
        guard report != nil, let scan = app.scan, let git = app.git else { return }
        let targets = scan.worktrees.filter { paths.contains($0.path) }
        let partial = await scanner(git: git).scan(
            targets,
            knownWorktrees: scan.worktrees,
            cwdIndex: await ProcessCwdIndex.capture(lsof: app.environment.tools.lsof),
            log: app.logEntries,
            includeLeftOut: false
        )
        // The report as it is now: a full scan may have ended meanwhile.
        report = report?.replacing(paths, with: partial)
    }

    func scanner(git: Git) -> ProjectFoldersScanner {
        ProjectFoldersScanner(git: git, environment: app.environment, sizeCache: FolderSizeCache(environment: app.environment))
    }

    private func receive(_ step: ProjectFoldersScanner.Progress) {
        guard isScanning else { return }
        progress = step
    }
}
