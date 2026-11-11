import CleanAppModel
import CleanCore
import SwiftUI

/// The Project folders screen: every checkout's light-clean folders (node_modules, .next, build…), grouped by
/// repo, filtered to the projects idle at least the threshold or all of them, with "Select all idle" and
/// "Clean selected…". Claude and Cursor worktrees are only counted in the footer.
struct ProjectsView: View {
    @Bindable var model: ProjectsModel
    let navigation: NavigationModel

    var body: some View {
        VStack(spacing: 0) {
            TestModeBanner(app: model.app)
            if let problem = model.app.problem {
                ProblemBanner(text: problem)
            }
            table
            Divider()
            ProjectsFooter(model: model) { navigation.show(.worktrees) }
        }
        .navigationTitle("Project folders")
        .toolbar { toolbar }
        .sheet(isPresented: $model.isShowingCleanSheet, onDismiss: { model.dismissClean() }) {
            ProjectsCleanSheet(model: model)
        }
        .task { await model.loadIfNeeded() }
    }

    private var table: some View {
        Table(of: ProjectTableItem.self, selection: tableSelection, sortOrder: $model.sortOrder) {
            TableColumn("Project", value: \ProjectTableItem.nameSortKey) { item in
                ProjectNameCell(item: item, isExpanded: isExpanded(item)) { toggle(item) }
            }
            .width(min: 140, ideal: 220)
            TableColumn("Idle", value: \ProjectTableItem.idleSortKey) { item in
                if let row = item.row {
                    Text(row.idleText).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .width(min: 44, ideal: 56)
            TableColumn("Folders", value: \ProjectTableItem.foldersText) { item in
                if let row = item.row {
                    Text(row.foldersText).lineLimit(1).truncationMode(.tail).help(row.foldersHelp)
                }
            }
            .width(min: 100, ideal: 180)
            TableColumn("Size", value: \ProjectTableItem.sizeSortKey) { item in
                ProjectSizeCell(item: item)
            }
            .width(min: 60, ideal: 78)
            TableColumn("Status", value: \ProjectTableItem.statusSortKey) { item in
                if let row = item.row {
                    if model.app.cleanupQueue.task(for: row.path) != nil {
                        QueuedItemStatus(queue: model.app.cleanupQueue, resource: row.path)
                    } else { ProjectStatusCell(row: row) }
                }
            }
            .width(min: 120, ideal: 300)
        } rows: {
            ForEach(model.tableItems) { item in
                TableRow(item)
            }
        }
        .contextMenu(forSelectionType: ProjectTableItem.ID.self) { ids in
            contextMenu(for: rowIDs(ids))
        } primaryAction: { ids in
            let rows = rows(rowIDs(ids))
            if rows.isEmpty {
                for case .group(let repoPath) in ids { model.toggleExpanded(repoPath) }
            } else {
                FolderActions.reveal(rows.map(\.url))
            }
        }
        .overlay { emptyState }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.report == nil {
            if model.isScanning || model.app.isScanning {
                ProgressView(ProjectsFooter.progressText(model))
            }
        } else if model.allRows.isEmpty {
            ContentUnavailableView(
                "No project folders found",
                systemImage: "cube.box",
                description: Text("No checkout under the scan roots has node_modules, build output or other folders "
                    + "that light clean can delete.")
            )
        } else if model.rows.isEmpty {
            ContentUnavailableView {
                Label("Nothing idle", systemImage: "checkmark.circle")
            } description: {
                Text("No project with folders to delete has been idle \(model.threshold) days or more. "
                    + "All shows the other \(DisplayText.projects(model.allRows.count)).")
            } actions: {
                Button("Show All") { model.filter = .all }
            }
        }
    }

    /// The table selects rows and group headers; the model keeps only the rows.
    private var tableSelection: Binding<Set<ProjectTableItem.ID>> {
        Binding(
            get: { Set(model.selection.map { ProjectTableItem.ID.project($0) }) },
            set: { model.selection = Set(rowIDs($0).filter { model.app.cleanupQueue.task(for: $0) == nil }) }
        )
    }

    private func isExpanded(_ item: ProjectTableItem) -> Bool {
        if case .group(let group) = item { return model.isExpanded(group.repoPath) }
        return true
    }

    private func toggle(_ item: ProjectTableItem) {
        if case .group(let group) = item { model.toggleExpanded(group.repoPath) }
    }

    private func rowIDs(_ ids: Set<ProjectTableItem.ID>) -> Set<ProjectRow.ID> {
        Set(ids.compactMap { id in
            if case .project(let rowID) = id { return rowID }
            return nil
        })
    }

    private func rows(_ ids: Set<ProjectRow.ID>) -> [ProjectRow] {
        model.rows.filter { ids.contains($0.id) }
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<ProjectRow.ID>) -> some View {
        let rows = rows(ids)
        if !rows.isEmpty {
            Button("Reveal in Finder") { FolderActions.reveal(rows.map(\.url)) }
            Button("Open in Terminal") { FolderActions.openInTerminal(rows.map(\.url)) }
            Button(rows.count == 1 ? "Copy Path" : "Copy Paths") { FolderActions.copy(rows.map(\.path)) }
            Divider()
            Button("Clean…") { Task { await model.beginClean(ids) } }
                .disabled(rows.contains { model.app.cleanupQueue.task(for: $0.path) != nil })
                .help(rows.contains { model.app.cleanupQueue.task(for: $0.path) != nil } ? CleanupQueue.lockedHelp : "Clean these folders after confirmation.")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { Task { await model.refreshAll() } } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Scan the worktrees and measure the project folders again")
            .disabled(model.isScanning || model.app.isScanning)
            Picker("Show", selection: $model.filter) {
                ForEach(ProjectsModel.Filter.allCases) { filter in
                    Text(model.filterTitle(filter)).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .help("Projects idle at least the threshold in Settings, or all of them")
            Button { model.selectAllIdle() } label: {
                Label("Select all idle", systemImage: "checklist")
            }
            .help("Select every project ready to clean: idle \(model.threshold)+ days, nothing running inside, not a "
                + "worktree that can be removed whole")
            .disabled(model.idleTotal.count == 0)
            Button { Task { await model.beginClean() } } label: {
                Label("Clean selected…", systemImage: "paintbrush")
            }
            .help("Delete the selected projects' dependency and build folders (you confirm first)")
            .disabled(!model.canClean)
        }
    }
}
