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
            .width(min: 120, ideal: 140, max: 180)
            TableColumn("Action") { row in
                if let loss = row.lossLine {
                    // Removed anyway: what was lost, in one line under the action.
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.actionText)
                        Text(loss).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    }
                    .help(row.notesHelp)
                } else {
                    Text(row.actionText)
                }
            }
            .width(min: 110, ideal: 170, max: 260)
            TableColumn("Path") { row in
                Text(row.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(row.notesHelp)
            }
            TableColumn("Branch") { row in
                Text(row.branchText)
            }
            .width(min: 80, ideal: 120, max: 220)
            TableColumn("Freed") { row in
                Text(row.freedText).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 72, max: 100)
            TableColumn("") { row in
                restoreCell(row)
            }
            .width(min: 90, ideal: 96, max: 120)
        }
        .contextMenu(forSelectionType: RemovalLogRow.ID.self) { ids in
            let rows = model.rows.filter { ids.contains($0.id) }
            if rows.count == 1, let row = rows.first, row.isRestorable {
                Button("Restore") { model.queueRestore(row.id) }
                    .disabled(model.app.cleanupQueue.task(for: row.path) != nil)
                    .help(model.app.cleanupQueue.task(for: row.path) != nil ? CleanupQueue.lockedHelp : "Restore from the kept branch or commit.")
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
        if model.app.cleanupQueue.task(for: row.path) != nil {
            QueuedItemStatus(queue: model.app.cleanupQueue, resource: row.path)
        } else if model.restoringID == row.id {
            ProgressView().controlSize(.small)
        } else if row.isRestorable {
            Button("Restore") { model.queueRestore(row.id) }
                .help("git worktree add from the kept branch; dependencies are not reinstalled")
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
            // A width from the HStack, then up to four lines: a fixedSize text next to a Spacer would be
            // measured at no width and make the whole screen thousands of points tall.
            Text(message.text)
                .textSelection(.enabled)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", action: dismiss)
        }
        .padding(10)
    }
}
