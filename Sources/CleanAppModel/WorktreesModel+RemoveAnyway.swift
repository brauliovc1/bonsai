import CleanCore
import Foundation

/// Remove anyway (PLAN §4.8): by hand, for ONE worktree whose blockers are all ones Bonsai can list exactly,
/// from its details panel or the More menu with that one row selected. The Delete key, Remove…, Remove all N and
/// a multi-row selection go through `beginRemoval`, which never removes a blocked worktree; auto mode and the
/// CLI have no way here at all.
extension WorktreesModel {
    /// The one selected row Remove anyway is offered for (by the last scan); nil with none or several selected,
    /// a repo folder selected, or a row it isn't offered for.
    public var removeAnywayRow: WorktreeRow? {
        guard selection.count == 1, let row = selectedRows.first, row.offersRemoveAnyway, app.cleanupQueue.task(for: row.path) == nil else { return nil }
        return row
    }

    public var canRemoveAnyway: Bool {
        removeAnywayRow != nil && !app.isQuitting
    }

    /// The More menu item's tooltip.
    public var removeAnywayHelp: String {
        if selectedRows.contains(where: { app.cleanupQueue.task(for: $0.path) != nil }) { return CleanupQueue.lockedHelp }
        if let row = removeAnywayRow, let list = row.assessment.removeAnyway.lossList {
            return RemoveAnywayText.help(list)
        }
        if selection.count != 1 || selectedRows.count != 1 {
            return "Select one blocked worktree: Remove anyway handles one at a time."
        }
        return selectedRows.first?.removeAnywayUnavailableText
            ?? "It can be removed the usual way, or nothing stops it that Remove anyway could override."
    }

    /// Opens the sheet for the one selected row and fills it from a fresh look: git's current record and a new
    /// inspection, from which the list is built. Nothing opens unless exactly that one row is selected and the
    /// last scan offered Remove anyway for it.
    public func beginRemoveAnyway() async {
        guard let row = removeAnywayRow, !app.isQuitting else { return }
        removeAnywaySheetToken += 1
        let token = removeAnywaySheetToken
        removeAnywayConfirmation = nil
        removeAnywayRefusal = nil
        removeAnywayOutcome = nil
        removeAnywayUnderstood = false
        isShowingRemoveAnywaySheet = true
        isPreparingRemoveAnyway = true
        let prepared = await prepareRemoveAnyway(row)
        // Closed (or opened again) while looking: drop this result.
        guard token == removeAnywaySheetToken, isShowingRemoveAnywaySheet else { return }
        switch prepared {
        case .success(let confirmation): removeAnywayConfirmation = confirmation
        case .failure(let refusal): removeAnywayRefusal = refusal.text
        }
        isPreparingRemoveAnyway = false
    }

    struct Refusal: Error {
        var text: String
    }

    /// A fresh look at `row`: the list to confirm, or why there is none now.
    func prepareRemoveAnyway(_ row: WorktreeRow) async -> Result<RemoveAnywayConfirmation, Refusal> {
        guard let git = app.git else { return .failure(Refusal(text: "git not found.")) }
        let (records, listings, failures) = await freshRecords(of: [row], git: git)
        guard let record = records.first ?? nil else {
            let why = failures[row.worktree.repoPath].map { "git could not list the repo's worktrees: \($0)" }
                ?? "git no longer lists it as a worktree of \(row.repoName); refresh the list"
            return .failure(Refusal(text: why.prefix(1).uppercased() + why.dropFirst() + "."))
        }
        let known = (app.scan?.worktrees ?? []) + listings.values.flatMap { $0 }
        let assessor = WorktreeAssessor(git: git, settings: app.settings, environment: app.environment)
        let fresh = await assessor.assess([record], knownWorktrees: known, sizes: app.scan?.sizes ?? [:])
        guard let assessment = fresh.first else { return .failure(Refusal(text: "It couldn't be looked at again.")) }
        switch assessment.removeAnyway {
        case .offered(let list):
            return .success(RemoveAnywayConfirmation(assessment: assessment, lossList: list))
        case .notNeeded:
            return .failure(Refusal(text: "Nothing stops a plain removal now: use Remove… instead."))
        case .unavailable(let reason):
            return .failure(Refusal(text: RemoveAnywayText.instead(for: reason)))
        }
    }

    /// Closes the sheet; not while the removal runs.
    public func dismissRemoveAnyway() {
        guard !isRemovingAnyway else { return }
        removeAnywaySheetToken += 1
        isShowingRemoveAnywaySheet = false
        isPreparingRemoveAnyway = false
        removeAnywayConfirmation = nil
        removeAnywayRefusal = nil
        removeAnywayOutcome = nil
        removeAnywayUnderstood = false
    }

    /// Removes the confirmed worktree anyway: only with `understood` (the sheet's checkbox), under the cleanup
    /// guard and `cleanup.lock`, through `Remover.removeAnyway`, which looks again right before the delete.
    @discardableResult
    public func confirmRemoveAnyway(_ confirmation: RemoveAnywayConfirmation, understood: Bool) async -> RemoveAnywayOutcome? {
        guard understood, !isRemovingAnyway, !isRemoving else { return nil }
        isRemovingAnyway = true
        let finished = await app.cleaningUp { await removeAnyway(confirmation) }
        let outcome = finished ?? .failed(app.busyReason)
        removeAnywayOutcome = outcome
        isRemovingAnyway = false
        if outcome.removed {
            selection.remove(confirmation.rowID)
            await app.cleanupFinished(removed: [confirmation.worktree])
        }
        return outcome
    }

    func removeAnyway(_ confirmation: RemoveAnywayConfirmation) async -> RemoveAnywayOutcome {
        guard let git = app.git else { return .failed("git not found") }
        if app.isQuitting { return .failed("the app is quitting") }
        let remover = Remover(git: git, settings: app.settings, environment: app.environment)
        do {
            let result = try await remover.removeAnyway(
                confirmation.worktree,
                confirmed: confirmation.lossList,
                expectation: confirmation.expectation,
                estimatedBytes: confirmation.assessment.estimatedBytes,
                knownWorktrees: app.scan?.worktrees ?? []
            )
            return .removed(result)
        } catch let mismatch as RemovalExpectation.Mismatch {
            return .changed(mismatch.changes)
        } catch {
            return .failed("\(error)")
        }
    }
}
