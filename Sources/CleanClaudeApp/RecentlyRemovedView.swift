import CleanAppModel
import SwiftUI

/// Recently removed: every cleanup in the log, newest first, with Restore for removed worktrees.
struct RecentlyRemovedView: View {
    @Bindable var model: RemovalsModel

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.logError {
                ProblemBanner(text: error)
            }
            table
            if let message = model.message {
                Divider()
                MessageBar(message: message) { model.message = nil }
            }
        }
        .navigationTitle("Recently removed")
    }

    private var table: some View {
        Table(model.rows, selection: $model.selection) {
            TableColumn("Date") { row in
                Text(row.date, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                    .monospacedDigit()
            }
            .width(min: 120, ideal: 150)
            TableColumn("Action") { row in
                Text(row.actionText)
            }
            .width(min: 110, ideal: 150)
            TableColumn("Path") { row in
                Text(row.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(row.notesHelp)
            }
            .width(min: 160, ideal: 320)
            TableColumn("Branch") { row in
                Text(row.branchText)
            }
            .width(min: 90, ideal: 150)
            TableColumn("Freed") { row in
                Text(row.freedText).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 76)
            TableColumn("") { row in
                restoreCell(row)
            }
            .width(min: 90, ideal: 110)
        }
        .contextMenu(forSelectionType: RemovalLogRow.ID.self) { ids in
            let rows = model.rows.filter { ids.contains($0.id) }
            if rows.count == 1, let row = rows.first, row.isRestorable {
                Button("Restore") { Task { await model.restore(row.id) } }
                    .disabled(model.restoringID != nil || model.app.isCleaningUp)
            }
            if !rows.isEmpty {
                Button(rows.count == 1 ? "Copy Path" : "Copy Paths") { FolderActions.copy(rows.map(\.path)) }
            }
        }
        .overlay {
            if model.rows.isEmpty, model.logError == nil {
                ContentUnavailableView(
                    "Nothing removed yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Every cleanup is logged here; removed worktrees can be restored.")
                )
            }
        }
    }

    @ViewBuilder
    private func restoreCell(_ row: RemovalLogRow) -> some View {
        if model.restoringID == row.id {
            ProgressView().controlSize(.small)
        } else if row.isRestorable {
            Button("Restore") { Task { await model.restore(row.id) } }
                .help("git worktree add from the kept branch; dependencies are not reinstalled")
                .disabled(model.restoringID != nil || model.app.isCleaningUp)
        } else if let restoredAt = row.restoredAt {
            Text("Restored \(restoredAt, format: .dateTime.month(.abbreviated).day())")
                .foregroundStyle(.secondary)
        }
    }
}

/// The last restore's result, dismissible.
private struct MessageBar: View {
    let message: RemovalsModel.Message
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: message.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(message.isError ? .red : .green)
            Text(message.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Dismiss", action: dismiss)
        }
        .padding(10)
    }
}
