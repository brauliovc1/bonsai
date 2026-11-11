import CleanAppModel
import SwiftUI

struct RemovalHistoryRow: View {
    let model: RemovalsModel
    let row: RemovalLogRow
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: row.isRestorable ? "arrow.triangle.branch" : "checkmark.circle").foregroundStyle(Palette.grey).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack { Text(row.actionText).fontWeight(.medium); Text(row.branchText).foregroundStyle(.secondary) }
                Text(row.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if let loss = row.lossLine { Text(loss).font(.callout).foregroundStyle(Palette.orange) }
                if let date = row.restoredAt {
                    Text("Restored \(date, format: .dateTime.month(.abbreviated).day())").font(.caption).foregroundStyle(.secondary)
                } else if !row.isRestorable {
                    Text(row.restoreNote)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).help(row.notesHelp)
            VStack(alignment: .trailing, spacing: 3) {
                SizeText(bytes: row.entry.freedBytes, isEstimate: false)
                Text("freed").font(.caption).foregroundStyle(.secondary)
            }
            if model.app.cleanupQueue.task(for: row.path) != nil {
                QueuedItemStatus(queue: model.app.cleanupQueue, resource: row.path)
            } else if row.isRestorable {
                Button("Restore") { model.queueRestore(row.id) }.help("Recreate the worktree from its kept branch or commit. Dependencies are downloaded again when needed.")
            }
        }
        .contextMenu { Button("Copy path") { FolderActions.copy([row.path]) } }
    }
}
