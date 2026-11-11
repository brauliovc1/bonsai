import CleanAppModel
import SwiftUI

struct CacheListRow: View {
    let model: CachesModel
    let row: CacheRow
    private var queued: Bool { model.app.cleanupQueue.task(for: model.queueResource(row.id)) != nil }
    var body: some View {
        HStack(spacing: 12) {
            if row.isDisplayOnly {
                Image(systemName: "lock").foregroundStyle(.tertiary).frame(width: 18)
            } else {
                Toggle("Select \(row.name)", isOn: Binding(get: { model.isSelected(row.id) }, set: { model.setSelected(row.id, $0) }))
                    .labelsHidden().toggleStyle(.checkbox).disabled(!row.isSelectable || queued)
                    .help(queued ? CleanupQueue.lockedHelp : row.statusText)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name).fontWeight(.medium)
                Text(row.folderText).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(row.folderText)
                Text(row.isDisplayOnly ? row.statusText : row.note).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let kept = row.keptText { Text(kept).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if queued { QueuedItemStatus(queue: model.app.cleanupQueue, resource: model.queueResource(row.id)) }
            else if !row.isDisplayOnly { StatusChip(words: row.statusWords, wraps: true).frame(maxWidth: 280, alignment: .trailing).help(row.statusText) }
            SizeText(bytes: row.bytes).frame(width: 85, alignment: .trailing)
        }
        .foregroundStyle(row.isDisplayOnly ? .secondary : .primary)
        .padding(.vertical, 3)
    }
}
