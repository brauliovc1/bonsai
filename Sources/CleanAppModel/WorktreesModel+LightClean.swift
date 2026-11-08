import CleanCore
import Foundation

extension WorktreesModel {
    /// How many worktrees the sheet looks at together.
    private static let lightCleanLookConcurrency = 4

    /// The sheet for the shown rows in `ids` (main checkouts too), from a fresh look at each one: git's
    /// current record of it, whether the folder is still that repo's worktree (the same read the removal
    /// sheet's assessment starts with: a stale record lists nothing), a process index taken now, and
    /// `LightCleanFinder` run again. Listed folders are the ones `confirmLightClean` deletes; the rest is
    /// shown with its reasons and left alone.
    public func prepareLightClean(_ ids: Set<WorktreeRow.ID>) async -> LightCleanConfirmation {
        let chosen = rows.filter { ids.contains($0.id) }
        guard !chosen.isEmpty else { return LightCleanConfirmation(items: []) }
        guard let git = app.git else {
            return LightCleanConfirmation(items: chosen.map { Self.leftAlone($0, because: "git not found") })
        }

        let (records, listings, failures) = await freshRecords(of: chosen, git: git)
        let known = (app.scan?.worktrees ?? []) + listings.values.flatMap { $0 }
        let index = await ProcessCwdIndex.capture(lsof: app.environment.tools.lsof)
        let finder = LightCleanFinder(git: git, du: app.environment.tools.du)
        let safety = SafetyCheck(git: git)

        // Everything the look needs is decided here; the finder runs for the rows that can be looked at.
        let jobs = zip(chosen, records).map { row, record -> (row: WorktreeRow, record: Worktree?, why: String?) in
            guard let record else {
                let why = failures[row.worktree.repoPath].map { "git could not list the repo's worktrees: \($0)" }
                    ?? "git no longer lists it as a worktree of \(row.repoName); refresh the list"
                return (row, nil, why)
            }
            return (row, record, LightCleaner.inUseReason(index, worktree: record.url)?.sentence)
        }
        let items = await BoundedConcurrency.map(jobs, limit: Self.lightCleanLookConcurrency) { job in
            guard let record = job.record else { return Self.leftAlone(job.row, because: job.why ?? "") }
            if let blocker = await safety.identityBlocker(of: record) {
                return LightCleanConfirmation.Item(worktree: record, findings: nil, blocker: blocker.sentence)
            }
            let findings = await finder.candidates(in: record, knownWorktrees: known)
            return LightCleanConfirmation.Item(worktree: record, findings: findings, blocker: job.why)
        }
        return LightCleanConfirmation(items: items)
    }

    /// Opens the light-clean sheet for `ids` (default: the selection) and fills it once the look is done.
    public func beginLightClean(_ ids: Set<WorktreeRow.ID>? = nil) async {
        let ids = ids ?? selection
        lightCleanSheetToken += 1
        let token = lightCleanSheetToken
        lightCleanReport = nil
        lightCleanConfirmation = nil
        isShowingLightCleanSheet = true
        isPreparingLightClean = true
        let prepared = await prepareLightClean(ids)
        // Closed (or opened again) while looking: drop this result.
        guard token == lightCleanSheetToken, isShowingLightCleanSheet else { return }
        lightCleanConfirmation = prepared
        isPreparingLightClean = false
    }

    /// Closes the sheet; not while folders are being deleted.
    public func dismissLightClean() {
        guard !isLightCleaning else { return }
        lightCleanSheetToken += 1
        isShowingLightCleanSheet = false
        isPreparingLightClean = false
        lightCleanConfirmation = nil
        lightCleanReport = nil
    }

    /// Deletes the listed folders, one worktree at a time, through `LightCleaner`, which checks each folder
    /// again right before it deletes it, and refuses a worktree that is no longer this repo's or whose branch
    /// or HEAD is not what the sheet showed. A folder that changed since the sheet listed it is refused with
    /// its reason, and nothing the sheet didn't list is touched. Then the rows' Deps are measured again and the
    /// worktrees are rescanned.
    @discardableResult
    public func confirmLightClean(_ confirmation: LightCleanConfirmation) async -> LightCleanReport {
        let items = confirmation.cleanable
        guard !items.isEmpty, !isLightCleaning else { return LightCleanReport(outcomes: []) }
        isLightCleaning = true
        lightCleansDone = 0
        let finished = await app.cleaningUp { await clean(items) }
        let busy = app.busyReason
        let outcomes = finished ?? items.map {
            LightCleanOutcome(item: $0, error: "\(busy); nothing was deleted")
        }
        let report = LightCleanReport(outcomes: outcomes)
        lightCleanReport = report
        isLightCleaning = false
        if finished != nil {
            await app.cleanupFinished()
            await measureDependencies(of: Set(items.map(\.id)))
        }
        return report
    }

    private func clean(_ items: [LightCleanConfirmation.Item]) async -> [LightCleanOutcome] {
        guard let git = app.git else {
            return items.map { LightCleanOutcome(item: $0, error: "git not found") }
        }
        let cleaner = LightCleaner(git: git, environment: app.environment)
        let known = app.scan?.worktrees ?? []
        var outcomes: [LightCleanOutcome] = []
        for item in items {
            do {
                let result = try await cleaner.clean(
                    item.worktree,
                    candidates: item.candidates,
                    knownWorktrees: known,
                    expectation: LightCleanExpectation(worktree: item.worktree)
                )
                outcomes.append(LightCleanOutcome(item: item, result: result))
            } catch {
                outcomes.append(LightCleanOutcome(item: item, error: "\(error)"))
            }
            lightCleansDone += 1
        }
        return outcomes
    }

    /// A sheet item for a worktree that is left alone as a whole.
    private nonisolated static func leftAlone(_ row: WorktreeRow, because why: String) -> LightCleanConfirmation.Item {
        LightCleanConfirmation.Item(worktree: row.worktree, findings: nil, blocker: why)
    }
}
