import CleanAppModel
import SwiftUI

/// The Worktrees toolbar (PLAN §8.4): the segmented filter with counts, Remove… (enabled only when the selection
/// holds something that can be removed; otherwise its tooltip says why) and More. ⌘R scans again.
struct WorktreesToolbar: ToolbarContent {
    @Bindable var model: WorktreesModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Show", selection: $model.filter) {
                ForEach(WorktreesModel.Filter.allCases) { filter in
                    Text(model.title(filter)).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help("Worktrees that can be removed, those with local work that needs you, or all of them")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { Task { await model.removeSelection() } } label: {
                Label("Remove…", systemImage: "trash")
            }
            .labelStyle(.titleAndIcon)
            .disabled(!model.canRemoveSelection)
            .help(model.removeDisabledReason ?? "Remove the selected worktrees (you confirm first)")
            Menu {
                WorktreesMoreMenu(model: model)
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .labelStyle(.titleAndIcon)
            .help("More actions for the selection")
            .background {
                // ⌘R from anywhere in the window (a menu item's shortcut only works while its menu is open).
                Button("Refresh") { model.app.requestRefresh() }
                    .keyboardShortcut("r")
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// The More menu: what the selection can do besides Remove…, and Refresh.
struct WorktreesMoreMenu: View {
    let model: WorktreesModel

    var body: some View {
        let folders = model.openableSelection
        Button("Prune missing folders…") { Task { await model.beginPrune() } }
            .disabled(model.pruneDisabledReason != nil)
            .help(model.pruneDisabledReason ?? "Clear git's records of worktrees whose folders are gone (you confirm first)")
        Button(cleanTitle) { Task { await model.beginLightClean() } }
            .disabled(!model.canCleanDependencies)
        // PLAN §4.8: one blocked worktree at a time, never from Remove… or the Delete key.
        Button(RemoveAnywayText.actionTitle) { Task { await model.beginRemoveAnyway() } }
            .disabled(!model.canRemoveAnyway)
            .help(model.removeAnywayHelp)
        Divider()
        Button("Show in Finder") { FolderActions.reveal(folders) }
            .disabled(folders.isEmpty)
        Button("Open in Terminal") { FolderActions.openInTerminal(folders) }
            .disabled(folders.isEmpty)
        Button(model.selectedPaths.count > 1 ? "Copy paths" : "Copy path") { FolderActions.copy(model.selectedPaths) }
            .disabled(model.selectedPaths.isEmpty)
        Divider()
        Button(model.isShowingDetails ? "Hide details" : "Show details") { model.isShowingDetails.toggle() }
        Button("Refresh") { model.app.requestRefresh() }
            .disabled(model.app.isScanning)
    }

    private var cleanTitle: String {
        model.selectedRows.count + model.selectedRepos.count > 1
            ? "Clean dependencies of these…" : "Clean dependencies of this worktree…"
    }
}

/// The right-click menu of the list, for the rows clicked (repo headers act on their repo folder).
struct WorktreeContextMenu: View {
    let model: WorktreesModel
    let ids: Set<WorktreeRow.ID>

    var body: some View {
        let rows = model.rows.filter { ids.contains($0.id) }
        let repos = model.groups.compactMap(\.main).filter { ids.contains($0.id) }
        let all = repos + rows
        let folders = all.filter(\.isOpenableFolder).map(\.url)
        if !all.isEmpty {
            if rows.contains(where: \.canRemove) {
                Button("Remove…") { Task { await model.beginRemoval(Set(rows.map(\.id))) } }
                    .disabled(model.app.isCleaningUp)
            }
            Button("Clean dependencies…") { Task { await model.beginLightClean(Set(all.map(\.id))) } }
                .disabled(model.app.isCleaningUp)
            Divider()
            Button("Show in Finder") { FolderActions.reveal(folders) }
                .disabled(folders.isEmpty)
            Button("Open in Terminal") { FolderActions.openInTerminal(folders) }
                .disabled(folders.isEmpty)
            Button(all.count == 1 ? "Copy path" : "Copy paths") { FolderActions.copy(all.map(\.path)) }
        }
        if rows.contains(where: \.isMissingFolder) {
            Divider()
            Button("Prune missing folders…") { Task { await model.beginPrune() } }
                .disabled(model.app.isCleaningUp)
        }
    }
}
