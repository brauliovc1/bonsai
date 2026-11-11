import CleanAppModel
import SwiftUI

struct ProjectFolderRow: View {
    let model: ProjectsModel
    let row: ProjectRow
    private var queued: Bool { model.app.cleanupQueue.task(for: row.path) != nil }
    var body: some View {
        HStack(spacing: 12) {
            Toggle("Select \(row.name)", isOn: Binding(get: { model.selection.contains(row.id) }, set: { on in
                if on { model.selection.insert(row.id) } else { model.selection.remove(row.id) }
            }))
            .labelsHidden().toggleStyle(.checkbox).disabled(queued || row.status.isBlocked)
            .help(queued ? CleanupQueue.lockedHelp : row.statusHelp)
            VStack(alignment: .leading, spacing: 5) {
                Text(row.name).fontWeight(.medium)
                Text(row.folderText).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Text(row.foldersText.replacingOccurrences(of: ", ", with: " · "))
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Palette.surface, in: Capsule()).lineLimit(1).help(row.foldersHelp)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if queued { QueuedItemStatus(queue: model.app.cleanupQueue, resource: row.path) }
            else { StatusChip(words: row.statusWords).help(row.statusHelp) }
            SizeText(bytes: row.measuredSizeBytes, hasUnknownParts: row.project.hasUnknownSizes).frame(width: 85, alignment: .trailing)
        }
        .contextMenu {
            Button("Show in Finder") { FolderActions.reveal([row.url]) }
            Button("Open in Terminal") { FolderActions.openInTerminal([row.url]) }
            Button("Copy path") { FolderActions.copy([row.path]) }
            Button("Clean dependencies…") { Task { await model.beginClean([row.id]) } }.disabled(queued || row.status.isBlocked)
        }
    }
}
