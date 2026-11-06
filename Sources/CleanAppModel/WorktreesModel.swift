import CleanCore
import Foundation
import Observation

/// The Worktrees screen: rows from the shared scan, sorting, filters, selection, and the remove and prune
/// flows. Removal goes only through `Remover` (manual mode), prune only through `Pruner`.
@MainActor
@Observable
public final class WorktreesModel {
    /// The `--status` groups of `clean-claude scan` (IN USE counts as blocked).
    public enum StatusFilter: String, CaseIterable, Sendable, Identifiable {
        case autoReady = "auto-ready"
        case safe
        case blocked

        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .autoReady: "Auto-ready"
            case .safe: "Safe"
            case .blocked: "Blocked or in use"
            }
        }
    }

    public static let idleChoices = [7, 30, 90]

    public let app: AppModel

    public var sortOrder = [KeyPathComparator(\WorktreeRow.repoName)]
    public var kindFilter: WorktreeKind?
    public var statusFilter: StatusFilter?
    /// Only rows idle at least this many days (idle unknown is left out).
    public var minimumIdleDays: Int?
    public var searchText = ""
    public var selection: Set<WorktreeRow.ID> = []

    /// The removal sheet's content; set by `beginRemoval`, cleared by `dismissRemoval`.
    public var confirmation: RemovalConfirmation?
    public private(set) var isRemoving = false
    public private(set) var removalsDone = 0
    /// Set when the confirmed removals are done; the sheet then shows it.
    public private(set) var report: RemovalReport?

    public private(set) var isPruning = false
    /// Set when a prune is done; the screen shows it until `dismissPruneOutcomes`.
    public var pruneOutcomes: [PruneOutcome]?

    public init(app: AppModel) {
        self.app = app
    }

    // MARK: - Rows

    /// Every worktree of the last scan, in scan order.
    public var allRows: [WorktreeRow] {
        app.assessments.enumerated().map { WorktreeRow(assessment: $1, scanOrder: $0) }
    }

    /// The rows shown: filtered, searched and sorted.
    public var rows: [WorktreeRow] {
        allRows.filter(matches).sorted(using: sortOrder + [KeyPathComparator(\WorktreeRow.scanOrder)])
    }

    /// The shown rows that are selected.
    public var selectedRows: [WorktreeRow] {
        rows.filter { selection.contains($0.id) }
    }

    /// Rows whose folder is gone ("Clean up missing folders" clears them).
    public var missingFolderRows: [WorktreeRow] {
        allRows.filter(\.isMissingFolder)
    }

    public var hasActiveFilters: Bool {
        kindFilter != nil || statusFilter != nil || minimumIdleDays != nil
    }

    public func clearFilters() {
        kindFilter = nil
        statusFilter = nil
        minimumIdleDays = nil
    }

    private func matches(_ row: WorktreeRow) -> Bool {
        if let kindFilter, row.kind != kindFilter { return false }
        if let statusFilter, row.status.group != statusFilter.rawValue { return false }
        if let minimumIdleDays {
            guard let days = row.idleDays, days >= minimumIdleDays else { return false }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return [row.repoName, row.branchText, row.path].contains { $0.localizedCaseInsensitiveContains(query) }
    }

    // MARK: - Remove

    /// The sheet for the shown rows in `ids`: allowed items with their notes and warnings, blocked items
    /// with their reasons (listed, never removed).
    public func prepareRemoval(_ ids: Set<WorktreeRow.ID>) -> RemovalConfirmation {
        RemovalConfirmation(items: rows.filter { ids.contains($0.id) }.map { .init(assessment: $0.assessment) })
    }

    /// Opens the sheet for `ids` (default: the selection).
    public func beginRemoval(_ ids: Set<WorktreeRow.ID>? = nil) {
        report = nil
        confirmation = prepareRemoval(ids ?? selection)
    }

    /// Closes the sheet; not while removals run.
    public func dismissRemoval() {
        guard !isRemoving else { return }
        confirmation = nil
        report = nil
    }

    /// Removes the allowed items one at a time through `Remover` (manual mode; it checks each one again
    /// right before removing), then rescans. Blocked items are never touched.
    @discardableResult
    public func confirmRemoval(_ confirmation: RemovalConfirmation) async -> [RemovalOutcome] {
        let items = confirmation.allowed
        guard !items.isEmpty, !isRemoving else { return [] }
        isRemoving = true
        removalsDone = 0
        let finished = await app.cleaningUp { await remove(items) }
        let report = finished ?? RemovalReport(
            outcomes: items.map { RemovalOutcome(item: $0, result: nil, error: "another cleanup is still running") },
            measuredFreedBytes: nil
        )
        self.report = report
        selection.subtract(report.outcomes.filter(\.removed).map(\.id))
        isRemoving = false
        if finished != nil { await app.cleanupFinished() }
        return report.outcomes
    }

    private func remove(_ items: [RemovalConfirmation.Item]) async -> RemovalReport {
        guard let git = app.git else {
            let outcomes = items.map { RemovalOutcome(item: $0, result: nil, error: "git not found") }
            return RemovalReport(outcomes: outcomes, measuredFreedBytes: nil)
        }
        let remover = Remover(git: git, settings: app.settings, environment: app.environment)
        let known = app.scan?.worktrees ?? []
        let probe = FreeSpaceProbe.volume(containing: items[0].worktree.repoURL)
        let before = probe.availableBytes()
        var outcomes: [RemovalOutcome] = []
        for item in items {
            do {
                let result = try await remover.remove(
                    item.worktree,
                    mode: .manual,
                    estimatedBytes: item.estimatedBytes,
                    knownWorktrees: known
                )
                outcomes.append(RemovalOutcome(item: item, result: result, error: nil))
            } catch {
                outcomes.append(RemovalOutcome(item: item, result: nil, error: "\(error)"))
            }
            removalsDone += 1
        }
        let after = probe.availableBytes()
        let freed = before.flatMap { before in after.map { max(0, $0 - before) } }
        return RemovalReport(outcomes: outcomes, measuredFreedBytes: freed)
    }

    // MARK: - Prune

    /// `git worktree prune` through `Pruner` for every repo with a missing folder, then rescans. A repo
    /// whose prune could hide work (an entry under /Volumes, an unreachable detached HEAD) is refused.
    @discardableResult
    public func prune() async -> [PruneOutcome] {
        var repos: [String] = []
        for row in missingFolderRows where !repos.contains(row.worktree.repoPath) {
            repos.append(row.worktree.repoPath)
        }
        guard !repos.isEmpty, !isPruning, let git = app.git else { return [] }
        isPruning = true
        let pruner = Pruner(git: git, environment: app.environment)
        let outcomes = await app.cleaningUp {
            var outcomes: [PruneOutcome] = []
            for repo in repos {
                outcomes.append(await Self.prune(repo, with: pruner))
            }
            return outcomes
        }
        pruneOutcomes = outcomes ?? []
        isPruning = false
        if outcomes != nil { await app.cleanupFinished() }
        return outcomes ?? []
    }

    private static func prune(_ repoPath: String, with pruner: Pruner) async -> PruneOutcome {
        do {
            let result = try await pruner.prune(repo: URL(fileURLWithPath: repoPath, isDirectory: true))
            return PruneOutcome(repoPath: repoPath, pruned: result.pruned, refusals: [], error: nil, warnings: result.warnings)
        } catch let refused as Pruner.Refused {
            return PruneOutcome(repoPath: repoPath, pruned: [], refusals: refused.refusals, error: nil, warnings: [])
        } catch {
            return PruneOutcome(repoPath: repoPath, pruned: [], refusals: [], error: "\(error)", warnings: [])
        }
    }

    public func dismissPruneOutcomes() {
        pruneOutcomes = nil
    }
}
