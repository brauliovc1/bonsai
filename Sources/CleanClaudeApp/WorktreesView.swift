import CleanAppModel
import CleanCore
import SwiftUI

/// Grouped worktrees, stable content filters, a details inspector and a pinned selection action.
/// Delete opens normal removal confirmation, Space toggles details and ⌘R refreshes.
struct WorktreesView: View {
    @Bindable var model: WorktreesModel
    /// False in a narrow window: the activity column goes first.
    @State private var showsActivity = true

    var body: some View {
        VStack(spacing: 0) {
            TestModeBanner(app: model.app)
            if let problem = model.app.problem {
                ProblemBanner(text: problem)
            }
            WorktreesSortBar(model: model)
            Divider()
            list
            Divider()
            bottomBar
        }
        // Measured outside the list and only when it crosses the line, so the list isn't reloaded from inside
        // its own layout.
        .onGeometryChange(for: Bool.self) { $0.size.width >= WorktreeColumns.activityMinimumListWidth } action: {
            showsActivity = $0
        }
        // Every screen keeps the same toolbar structure, title included: removing the title here alone moved the
        // sidebar when switching to this screen (11-09). At narrow widths the search field collapses and what
        // doesn't fit goes to the toolbar's overflow menu.
        .navigationTitle("Worktrees")
        .background {
            // ⌘R from anywhere on the screen, also when More sits in the overflow menu.
            Button("Refresh") { model.app.requestRefresh() }
                .keyboardShortcut("r")
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Repo, branch, folder or commit")
        .toolbar { WorktreesToolbar(model: model) }
        .inspector(isPresented: $model.isShowingDetails) {
            WorktreeDetailsView(model: model)
                .inspectorColumnWidth(min: 280, ideal: 320, max: 460)
        }
        .sheet(isPresented: $model.isShowingRemovalSheet, onDismiss: { model.dismissRemoval() }) {
            RemovalConfirmationSheet(model: model)
        }
        .sheet(isPresented: $model.isShowingRemoveAnywaySheet, onDismiss: { model.dismissRemoveAnyway() }) {
            RemoveAnywaySheet(model: model)
        }
        .sheet(isPresented: $model.isShowingLightCleanSheet, onDismiss: { model.dismissLightClean() }) {
            LightCleanSheet(model: model)
        }
        .sheet(isPresented: $model.isShowingPruneSheet, onDismiss: { model.dismissPrune() }) {
            PruneSheet(model: model)
        }
        .task(id: model.app.scanCount) { await model.computeDependenciesIfNeeded() }
    }

    private var list: some View {
        List(selection: Binding(get: { model.selection }, set: { ids in
            model.selection = Set(ids.filter { model.app.cleanupQueue.task(for: $0.path) == nil })
        })) {
            if model.groupsByRepo {
                ForEach(model.groups) { group in
                    RepoGroupHeader(model: model, group: group)
                        .tag(group.main?.id ?? WorktreeRow.ID(repoPath: group.repoPath, path: group.repoPath))
                    if model.isExpanded(group.repoPath) {
                        ForEach(group.rows) { row in
                            WorktreeListRow(row: row, showsActivity: showsActivity, queue: model.app.cleanupQueue)
                                .tag(row.id)
                        }
                    }
                }
            } else {
                // One list across repos, each row with its repo's name.
                ForEach(model.flatRows) { row in
                    WorktreeListRow(row: row, showsActivity: showsActivity, showsRepo: true, queue: model.app.cleanupQueue)
                        .tag(row.id)
                }
            }
        }
        .listStyle(.inset)
        .onDeleteCommand { Task { await model.removeSelection() } }
        .onKeyPress(.space) {
            model.isShowingDetails.toggle()
            return .handled
        }
        .contextMenu(forSelectionType: WorktreeRow.ID.self) { ids in
            WorktreeContextMenu(model: model, ids: ids)
        } primaryAction: { ids in
            // A double-click on a repo header opens or closes it; on worktrees, shows them in Finder.
            let repos = model.groups.filter { group in group.main.map { ids.contains($0.id) } ?? false }
            if !repos.isEmpty, ids.count == repos.count {
                for group in repos { model.toggleExpanded(group.repoPath) }
            } else {
                FolderActions.reveal(model.rows.filter { ids.contains($0.id) && $0.isOpenableFolder }.map(\.url))
            }
        }
        .overlay { emptyState }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if let text = model.selectionText {
            SelectionBar(text: text) {
                Button("Clear") { model.selection.removeAll() }
                Button("Remove…") { Task { await model.removeSelection() } }
                    .disabled(!model.canRemoveSelection)
                    .help(model.removeDisabledReason ?? "Remove the selected worktrees (you confirm first)")
            }
        } else {
            VStack(spacing: 0) {
                SelectionBar(text: "Select worktrees to review removal") { EmptyView() }
                ScanStatusBar(app: model.app, shown: model.rows.count, total: model.linkedRows.count)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.groups.isEmpty, !model.app.isScanning {
            if model.linkedRows.isEmpty {
                EmptyState(systemImage: "arrow.triangle.branch", headline: "No worktrees", line: noWorktreesLine)
            } else if !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            } else {
                filterEmptyState
            }
        }
    }

    @ViewBuilder
    private var filterEmptyState: some View {
        switch model.filter {
        case .canRemove:
            EmptyState(
                systemImage: "checkmark.circle", headline: "Nothing to remove",
                line: "Every worktree has work in it or is in use. Needs attention lists the ones with local work.",
                actionTitle: "Show all"
            ) { model.filter = .all }
        case .needsAttention:
            EmptyState(
                systemImage: "checkmark.circle", headline: "Nothing needs your attention",
                line: "No worktree has local work that keeps it.", actionTitle: "Show all"
            ) { model.filter = .all }
        case .all:
            EmptyState(systemImage: "arrow.triangle.branch", headline: "No worktrees", line: noWorktreesLine)
        }
    }

    private var noWorktreesLine: String {
        let roots = model.app.roots.map(\.path).joined(separator: ", ")
        if model.allRows.isEmpty {
            return roots.isEmpty ? "There are no folders to scan. Add one in Settings." : "No git repos under \(roots)."
        }
        return "These repos have no worktrees besides their repo folders."
    }
}
