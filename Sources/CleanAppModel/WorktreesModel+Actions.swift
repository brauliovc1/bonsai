import CleanCore
import Foundation

/// What the toolbar, the keyboard, the group headers and the selection bar may do with the selection. Remove…
/// is enabled only when the selection holds something a removal by hand accepts, so the removal sheet never
/// opens to say "nothing can be removed", and a repo folder (main checkout) is never part of a removal.
extension WorktreesModel {
    /// The shown, selected worktrees a removal by hand accepts.
    public var removableSelection: [WorktreeRow] {
        selectedRows.filter(\.canRemove)
    }

    public var canRemoveSelection: Bool {
        !removableSelection.isEmpty && !app.isCleaningUp && !isRemoving
    }

    /// Remove…'s tooltip when it is disabled; nil when it is enabled.
    public var removeDisabledReason: String? {
        if canRemoveSelection { return nil }
        if app.isCleaningUp || isRemoving { return app.busySentence }
        if selectedRows.isEmpty {
            return selectedRepos.isEmpty ? "Select the worktrees to remove." : WorktreeStatusText.repoFolderSentence
        }
        if selectedRows.count == 1, let row = selectedRows.first {
            return "It can't be removed: \(row.explanation)" + (row.offersRemoveAnyway ? " " + RemoveAnywayText.detailsHint : "")
        }
        return "None of the selected worktrees can be removed. Their details say why."
    }

    /// "Remove…" from the toolbar, the Delete key or the selection bar: opens the confirmation for the selected
    /// worktrees, never removes anything by itself. Does nothing when nothing selected can be removed.
    public func removeSelection() async {
        guard canRemoveSelection else { return }
        await beginRemoval(Set(selectedRows.map(\.id)))
    }

    /// "Remove all N" on a group header: the confirmation for the group's shown worktrees that can be removed.
    public func removeAll(in group: WorktreeGroup) async {
        let ids = Set(group.removableRows.map(\.id))
        guard !ids.isEmpty, !app.isCleaningUp else { return }
        await beginRemoval(ids)
    }

    /// "Clean dependencies…" on a group header: the existing clean sheet for the repo folder.
    public func cleanDependencies(of group: WorktreeGroup) async {
        guard let main = group.main, !app.isCleaningUp else { return }
        await beginLightClean([main.id])
    }

    /// "Clean dependencies of this worktree…" in the More menu: the selected worktrees and repo folders.
    public var canCleanDependencies: Bool {
        !(selectedRows.isEmpty && selectedRepos.isEmpty) && !app.isCleaningUp
    }

    /// The selection bar: "3 selected · 1.2 GB can be freed"; nil with nothing selected.
    public var selectionText: String? {
        let selected = selectedRows.count + selectedRepos.count
        guard selected > 0 else { return nil }
        let removable = removableSelection
        let bytes = removable.compactMap(\.sizeBytes).reduce(0, +)
        guard !removable.isEmpty else { return "\(selected) selected · nothing to remove" }
        let what = removable.count == selected ? "" : " (\(removable.count) can be removed)"
        return "\(selected) selected\(what) · \(DisplayText.bytes(bytes))"
    }

    /// The selected worktrees' and repo folders' folders that exist as real folders, for Finder and Terminal.
    public var openableSelection: [URL] {
        (selectedRepos + selectedRows).filter(\.isOpenableFolder).map(\.url)
    }

    public var selectedPaths: [String] {
        (selectedRepos + selectedRows).map(\.path)
    }
}
