import CleanAppModel
import CleanCore
import SwiftUI

/// The Worktrees screen: every worktree of the last scan with its verdict; remove and prune from here.
struct WorktreesView: View {
    @Bindable var model: WorktreesModel

    var body: some View {
        VStack(spacing: 0) {
            if let problem = model.app.problem {
                ProblemBanner(text: problem)
            }
            table
            Divider()
            ScanStatusBar(app: model.app, shown: model.rows.count, total: model.allRows.count)
        }
        .navigationTitle("Worktrees")
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Repo, branch or path")
        .toolbar { toolbar }
        .sheet(isPresented: $model.isShowingRemovalSheet, onDismiss: { model.dismissRemoval() }) {
            RemovalConfirmationSheet(model: model)
        }
    }

    private var table: some View {
        Table(model.rows, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn("Repo", value: \.repoName) { row in
                Text(row.repoName).help(row.path)
            }
            .width(min: 90, ideal: 130)
            TableColumn("Branch", value: \.branchText) { row in
                Text(row.branchText).help(row.path)
            }
            .width(min: 110, ideal: 190)
            TableColumn("Kind", value: \.kindText) { row in
                Badge(kind: row.kind)
            }
            .width(min: 56, ideal: 66)
            TableColumn("Size", value: \.sizeSortKey) { row in
                Text(row.sizeText).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 64, ideal: 78)
            TableColumn("Idle", value: \.idleSortKey) { row in
                Text(row.idleText).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 48, ideal: 58)
            TableColumn("Status", value: \.statusSortKey) { row in
                StatusCell(row: row)
            }
            .width(min: 150, ideal: 260)
        }
        .sheet(isPresented: $model.isShowingPruneSheet, onDismiss: { model.dismissPrune() }) {
            PruneSheet(model: model)
        }
        .contextMenu(forSelectionType: WorktreeRow.ID.self) { ids in
            contextMenu(for: ids)
        } primaryAction: { ids in
            FolderActions.reveal(rows(ids).filter(\.isOpenableFolder).map(\.url))
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
            Button { Task { await model.beginRemoval() } } label: {
                Label("Remove…", systemImage: "trash")
            }
            .help("Remove the selected worktrees (you confirm first)")
            .disabled(model.selectedRows.isEmpty || model.app.isCleaningUp)
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
