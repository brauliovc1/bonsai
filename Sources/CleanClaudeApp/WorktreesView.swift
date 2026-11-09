import CleanAppModel
import CleanCore
import SwiftUI

/// The Worktrees screen: every worktree of the last scan, grouped by repo, with its last commit, folder,
/// verdict and Deps; a details panel for the selection; remove, prune and light clean from here.
struct WorktreesView: View {
    @Bindable var model: WorktreesModel

    var body: some View {
        VStack(spacing: 0) {
            if let testMode = model.app.testModeText {
                TestModeBanner(text: testMode)
            }
            if let problem = model.app.problem {
                ProblemBanner(text: problem)
            }
            table
            Divider()
            ScanStatusBar(app: model.app, shown: model.rows.count, total: model.allRows.count)
        }
        .navigationTitle("Worktrees")
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Repo, branch, folder, remote or commit")
        .toolbar { toolbar }
        .inspector(isPresented: $model.isShowingDetails) {
            WorktreeDetailsView(model: model)
                .inspectorColumnWidth(min: 280, ideal: 330, max: 460)
        }
        .sheet(isPresented: $model.isShowingRemovalSheet, onDismiss: { model.dismissRemoval() }) {
            RemovalConfirmationSheet(model: model)
        }
        .sheet(isPresented: $model.isShowingLightCleanSheet, onDismiss: { model.dismissLightClean() }) {
            LightCleanSheet(model: model)
        }
        .task(id: model.app.scanCount) { await model.computeDependenciesIfNeeded() }
    }

    private var table: some View {
        Table(of: WorktreeTableItem.self, selection: tableSelection, sortOrder: tableSortOrder) {
            TableColumn("Worktree", value: \WorktreeTableItem.nameSortKey) { WorktreeNameCell(item: $0) }
                .width(min: 120, ideal: 170)
            TableColumn("Kind", value: \WorktreeTableItem.kindText) { item in
                if let row = item.row { Badge(kind: row.kind) }
            }
            .width(min: 54, ideal: 62)
            TableColumn("Last commit", value: \WorktreeTableItem.lastCommitSortKey) { LastCommitCell(item: $0) }
                .width(min: 150, ideal: 240)
            TableColumn("Folder", value: \WorktreeTableItem.folderText) { FolderCell(item: $0) }
                .width(min: 110, ideal: 210)
            TableColumn("Size", value: \WorktreeTableItem.sizeSortKey) { SizeCell(item: $0) }
                .width(min: 60, ideal: 74)
            TableColumn("Deps", value: \WorktreeTableItem.dependencySortKey) { item in
                if let row = item.row { DepsCell(row: row) }
            }
            .width(min: 60, ideal: 74)
            TableColumn("Idle", value: \WorktreeTableItem.idleSortKey) { item in
                if let row = item.row {
                    Text(row.idleText).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .width(min: 44, ideal: 52)
            TableColumn("Status", value: \WorktreeTableItem.statusSortKey) { item in
                if let row = item.row { StatusCell(row: row) }
            }
            .width(min: 130, ideal: 210)
        } rows: {
            ForEach(model.groups) { group in
                DisclosureTableRow(WorktreeTableItem.group(group), isExpanded: expanded(group)) {
                    ForEach(group.rows) { row in
                        TableRow(WorktreeTableItem.worktree(row))
                    }
                }
            }
        }
        .sheet(isPresented: $model.isShowingPruneSheet, onDismiss: { model.dismissPrune() }) {
            PruneSheet(model: model)
        }
        .contextMenu(forSelectionType: WorktreeTableItem.ID.self) { ids in
            contextMenu(for: rowIDs(ids))
        } primaryAction: { ids in
            FolderActions.reveal(rows(rowIDs(ids)).filter(\.isOpenableFolder).map(\.url))
        }
        .overlay {
            if model.allRows.isEmpty, !model.app.isScanning {
                ContentUnavailableView("No worktrees found", systemImage: "folder",
                                       description: Text(emptyDescription))
            } else if model.rows.isEmpty, !model.allRows.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            }
        }
    }

    /// The table selects rows and group headers; the model keeps only the rows.
    private var tableSelection: Binding<Set<WorktreeTableItem.ID>> {
        Binding(
            get: { Set(model.selection.map { WorktreeTableItem.ID.worktree($0) }) },
            set: { model.selection = rowIDs($0) }
        )
    }

    private var tableSortOrder: Binding<[KeyPathComparator<WorktreeTableItem>]> {
        Binding(
            get: { WorktreeTableItem.tableSortOrder(model.sortOrder) },
            set: { order in
                let rows = WorktreeTableItem.rowSortOrder(order)
                if !rows.isEmpty { model.sortOrder = rows }
            }
        )
    }

    private func expanded(_ group: WorktreeGroup) -> Binding<Bool> {
        Binding(
            get: { model.isExpanded(group.repoPath) },
            set: { model.setExpanded($0, repo: group.repoPath) }
        )
    }

    private func rowIDs(_ ids: Set<WorktreeTableItem.ID>) -> Set<WorktreeRow.ID> {
        Set(ids.compactMap { id in
            if case .worktree(let rowID) = id { return rowID }
            return nil
        })
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<WorktreeRow.ID>) -> some View {
        let rows = rows(ids)
        let folders = rows.filter(\.isOpenableFolder).map(\.url)
        if !rows.isEmpty {
            Button("Reveal in Finder") { FolderActions.reveal(folders) }
                .disabled(folders.isEmpty)
            Button("Open in Terminal") { FolderActions.openInTerminal(folders) }
                .disabled(folders.isEmpty)
            Button(rows.count == 1 ? "Copy Path" : "Copy Paths") { FolderActions.copy(rows.map(\.path)) }
            Divider()
            Button("Light clean…") { Task { await model.beginLightClean(ids) } }
                .disabled(model.app.isCleaningUp)
            Button("Remove…") { Task { await model.beginRemoval(ids) } }
                .disabled(model.app.isCleaningUp)
        }
        if rows.contains(where: \.isMissingFolder) {
            Button("Clean up missing folders…") { Task { await model.beginPrune() } }
                .disabled(model.app.isCleaningUp)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { model.app.requestRefresh() } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Scan again")
            .disabled(model.app.isScanning)
            WorktreesFilterMenu(model: model)
            if !model.missingFolderRows.isEmpty {
                Button { Task { await model.beginPrune() } } label: {
                    Label("Clean up missing folders…", systemImage: "folder.badge.minus")
                }
                .help("git worktree prune for the worktrees whose folders are gone")
                .disabled(model.app.isCleaningUp)
            }
            Button { Task { await model.computeDependencies() } } label: {
                Label("Compute deps sizes", systemImage: "scalemass")
            }
            .help("Measure the dependency and build folders light clean could delete in every worktree")
            .disabled(model.isMeasuringDependencies || model.allRows.isEmpty)
            Button { Task { await model.beginLightClean() } } label: {
                Label("Light clean…", systemImage: "paintbrush")
            }
            .help("Delete the selected worktrees' node_modules, build output and other regenerable folders (you confirm first)")
            .disabled(model.selectedRows.isEmpty || model.app.isCleaningUp)
            Button { Task { await model.beginRemoval() } } label: {
                Label("Remove…", systemImage: "trash")
            }
            .help("Remove the selected worktrees (you confirm first)")
            .disabled(model.selectedRows.isEmpty || model.app.isCleaningUp)
            Button { model.isShowingDetails.toggle() } label: {
                Label("Details", systemImage: "sidebar.trailing")
            }
            .help(model.isShowingDetails ? "Hide the details panel" : "Show the details panel")
        }
    }

    private func rows(_ ids: Set<WorktreeRow.ID>) -> [WorktreeRow] {
        model.rows.filter { ids.contains($0.id) }
    }

    private var emptyDescription: String {
        let roots = model.app.roots.map(\.path).joined(separator: ", ")
        return roots.isEmpty ? "There are no scan roots." : "No git repos under \(roots)."
    }
}
