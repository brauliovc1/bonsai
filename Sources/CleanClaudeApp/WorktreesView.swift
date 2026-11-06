import CleanAppModel
import CleanCore
import SwiftUI

/// The Worktrees screen: every worktree of the last scan with its verdict; remove and prune from here.
struct WorktreesView: View {
    @Bindable var model: WorktreesModel
    @State private var confirmingPrune = false

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
        .sheet(item: $model.confirmation) { confirmation in
            RemovalConfirmationSheet(model: model, confirmation: confirmation)
        }
        .confirmationDialog(
            "Clean up \(model.missingFolderRows.count == 1 ? "1 missing folder" : "\(model.missingFolderRows.count) missing folders")?",
            isPresented: $confirmingPrune
        ) {
            Button("Clean Up") { Task { await model.prune() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("git forgets the worktrees whose folders are gone (git worktree prune). Their branches are kept.")
        }
        .alert("Missing folders", isPresented: pruneAlertShown) {
            Button("OK") { model.dismissPruneOutcomes() }
        } message: {
            Text((model.pruneOutcomes ?? []).map(\.summary).joined(separator: "\n"))
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
        .contextMenu(forSelectionType: WorktreeRow.ID.self) { ids in
            contextMenu(for: ids)
        } primaryAction: { ids in
            FolderActions.reveal(rows(ids).map(\.url).filter(FolderActions.exists))
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
        let existing = rows.map(\.url).filter(FolderActions.exists)
        if !rows.isEmpty {
            Button("Reveal in Finder") { FolderActions.reveal(existing) }
                .disabled(existing.isEmpty)
            Button("Open in Terminal") { FolderActions.openInTerminal(existing) }
                .disabled(existing.isEmpty)
            Button(rows.count == 1 ? "Copy Path" : "Copy Paths") { FolderActions.copy(rows.map(\.path)) }
            Divider()
            Button("Remove…") { model.beginRemoval(ids) }
                .disabled(model.app.isCleaningUp)
        }
        if rows.contains(where: \.isMissingFolder) {
            Button("Clean up missing folders…") { confirmingPrune = true }
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
                Button { confirmingPrune = true } label: {
                    Label("Clean up missing folders…", systemImage: "folder.badge.minus")
                }
                .help("git worktree prune for the worktrees whose folders are gone")
                .disabled(model.app.isCleaningUp)
            }
            Button { model.beginRemoval() } label: {
                Label("Remove…", systemImage: "trash")
            }
            .help("Remove the selected worktrees (you confirm first)")
            .disabled(model.selectedRows.isEmpty || model.app.isCleaningUp)
        }
    }

    private func rows(_ ids: Set<WorktreeRow.ID>) -> [WorktreeRow] {
        model.rows.filter { ids.contains($0.id) }
    }

    private var pruneAlertShown: Binding<Bool> {
        Binding(get: { model.pruneOutcomes != nil }, set: { if !$0 { model.dismissPruneOutcomes() } })
    }

    private var emptyDescription: String {
        let roots = model.app.roots.map(\.path).joined(separator: ", ")
        return roots.isEmpty ? "There are no scan roots." : "No git repos under \(roots)."
    }
}
