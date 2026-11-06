import CleanCore
import Foundation

extension WorktreesModel {
    /// The sheet for the shown rows in `ids`, from a fresh look at each one, because the last scan can be
    /// old: git's current record of it (another worktree may live at the path now) and a fresh assessment.
    /// Allowed items carry what they were confirmed with; blocked items are listed, never removed.
    public func prepareRemoval(_ ids: Set<WorktreeRow.ID>) async -> RemovalConfirmation {
        let chosen = rows.filter { ids.contains($0.id) }
        guard !chosen.isEmpty else { return RemovalConfirmation(items: []) }
        guard let git = app.git else {
            return RemovalConfirmation(items: chosen.map { Self.blocked($0, because: "git not found") })
        }

        let (records, listings, failures) = await freshRecords(of: chosen, git: git)
        let known = (app.scan?.worktrees ?? []) + listings.values.flatMap { $0 }
        let assessor = WorktreeAssessor(git: git, settings: app.settings, environment: app.environment)
        var fresh = await assessor.assess(records.compactMap { $0 }, knownWorktrees: known, sizes: app.scan?.sizes ?? [:])
            .makeIterator()

        let items = zip(chosen, records).map { row, record -> RemovalConfirmation.Item in
            guard record != nil, let assessment = fresh.next() else {
                let why = failures[row.worktree.repoPath].map { "git could not list the repo's worktrees: \($0)" }
                    ?? "git no longer lists it as a worktree of \(row.repoName); refresh the list"
                return Self.blocked(row, because: why)
            }
            return RemovalConfirmation.Item(assessment: assessment)
        }
        return RemovalConfirmation(items: items)
    }

    /// Opens the sheet for `ids` (default: the selection) and fills it once the fresh look is done.
    public func beginRemoval(_ ids: Set<WorktreeRow.ID>? = nil) async {
        let ids = ids ?? selection
        removalSheetToken += 1
        let token = removalSheetToken
        report = nil
        confirmation = nil
        isShowingRemovalSheet = true
        isPreparingRemoval = true
        let prepared = await prepareRemoval(ids)
        // Closed (or opened again) while looking: drop this result.
        guard token == removalSheetToken, isShowingRemovalSheet else { return }
        confirmation = prepared
        isPreparingRemoval = false
    }

    /// Closes the sheet; not while removals run.
    public func dismissRemoval() {
        guard !isRemoving else { return }
        removalSheetToken += 1
        isShowingRemovalSheet = false
        isPreparingRemoval = false
        confirmation = nil
        report = nil
    }

    /// Removes the allowed items one at a time through `Remover` (manual mode), each refused if it changed
    /// in any way since it was confirmed, then rescans. Blocked items are never touched.
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
        // One reading per volume the items are on, before and after. Freed space is the sum of the gains on
        // the volumes where something was removed (elsewhere a gain is someone else's doing).
        let itemVolumes = items.map { volumeOf($0.worktree.url) }
        var volumes: [URL] = []
        for case let volume? in itemVolumes where !volumes.contains(volume) {
            volumes.append(volume)
        }
        let before = volumes.map(freeBytes)
        var outcomes: [RemovalOutcome] = []
        for item in items {
            do {
                let result = try await remover.remove(
                    item.worktree,
                    mode: .manual,
                    estimatedBytes: item.estimatedBytes,
                    knownWorktrees: known,
                    expectation: item.expectation
                )
                outcomes.append(RemovalOutcome(item: item, result: result, error: nil))
            } catch let mismatch as RemovalExpectation.Mismatch {
                let text = "It changed since you confirmed it, so it was left alone; review it again. "
                    + mismatch.changes.joined(separator: " ")
                outcomes.append(RemovalOutcome(item: item, result: nil, error: text, changedSinceConfirmed: true))
            } catch {
                outcomes.append(RemovalOutcome(item: item, result: nil, error: "\(error)"))
            }
            removalsDone += 1
        }
        let after = volumes.map(freeBytes)
        let removedOn = Set(zip(outcomes, itemVolumes).compactMap { outcome, volume in outcome.removed ? volume : nil })
        let gains = volumes.indices.filter { removedOn.contains(volumes[$0]) }.compactMap { index in
            before[index].flatMap { before in after[index].map { max(0, $0 - before) } }
        }
        return RemovalReport(outcomes: outcomes, measuredFreedBytes: gains.isEmpty ? nil : gains.reduce(0, +))
    }

    /// git's current record of each row's worktree (nil when git no longer lists it), the repos' full
    /// listings, and why a repo could not be listed. Shared by the remove and light-clean sheets.
    func freshRecords(
        of chosen: [WorktreeRow],
        git: Git
    ) async -> (records: [Worktree?], listings: [String: [Worktree]], failures: [String: String]) {
        let scanner = WorktreeScanner(git: git, cursorWorktreesDirectory: app.environment.cursorWorktreesDirectory)
        var listings: [String: [Worktree]] = [:]
        var failures: [String: String] = [:]
        for repo in Set(chosen.map(\.worktree.repoPath)) {
            do {
                listings[repo] = try await scanner.worktrees(in: URL(fileURLWithPath: repo, isDirectory: true))
            } catch {
                failures[repo] = "\(error)"
            }
        }
        let records: [Worktree?] = chosen.map { row in
            listings[row.worktree.repoPath]?.first { CanonicalPath.same($0.url, row.url) }
        }
        return (records, listings, failures)
    }

    /// A blocked sheet item for a row that can't be looked at afresh.
    private static func blocked(_ row: WorktreeRow, because why: String) -> RemovalConfirmation.Item {
        let report = SafetyReport(blockers: [.gitError(why)], notes: [], autoBlockers: [.gitError(why)])
        let assessment = WorktreeAssessment(worktree: row.worktree, idle: .unknown, safety: report,
                                            estimatedBytes: row.sizeBytes)
        return RemovalConfirmation.Item(assessment: assessment)
    }
}
