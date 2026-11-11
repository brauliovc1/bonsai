import CleanAppModel
import SwiftUI

struct DerivedDataView: View {
    @Bindable var model: DerivedDataModel
    @State private var sort: ContentSort = .size
    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Xcode DerivedData", subtitle: "Old build folders whose projects are gone can be deleted.") {
                Button("Delete selected…") { Task { await model.beginDelete() } }.disabled(!model.canDelete)
            }.padding(20)
            if let refusal = model.refusal { ProblemBanner(text: "Can't read this DerivedData folder: \(refusal)") }
            HStack {
                ContentSortBar(selection: $sort)
                Button("Select all orphaned") { model.selection = model.selectableIDs }.disabled(model.selectableIDs.isEmpty)
                Button("Refresh") { Task { await model.refresh() } }.disabled(model.isScanning)
            }.padding(.trailing, 20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if model.report == nil { ProgressView("Reading DerivedData…").frame(maxWidth: .infinity).padding(30) }
                    else if model.orphanRows.isEmpty {
                        EmptyState(systemImage: "hammer", headline: "No orphaned build folders", line: "Xcode's current projects and shared caches are kept.")
                            .frame(maxWidth: .infinity)
                    } else {
                        section("Ready to delete", rows: model.rows.filter(\.isSelectable))
                    }
                    let kept = model.rows.filter { !$0.isSelectable }
                    if !kept.isEmpty { section("Kept for Xcode", rows: kept) }
                    ForEach(model.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(Palette.orange)
                    }
                }.padding(20)
            }
            if !model.selectedOrphans.isEmpty {
                SelectionBar(text: "\(model.selectedOrphans.count) selected · \(CleanupPresentation.estimate(model.selectedOrphans.map(\.bytes)))") {
                    Button("Delete selected…") { Task { await model.beginDelete() } }.disabled(!model.canDelete)
                }
            }
        }
        .onChange(of: sort) { _, value in
            model.sortOrder = value == .size ? [KeyPathComparator(\DerivedDataRow.sizeSortKey, order: .reverse)] : [KeyPathComparator(\DerivedDataRow.name)]
        }
        .navigationTitle("Xcode DerivedData")
        .sheet(isPresented: $model.isShowingDeleteSheet, onDismiss: { model.dismissDelete() }) { DerivedDataDeleteSheet(model: model) }
        .task { await model.loadIfNeeded() }
    }
    private func section(_ title: String, rows: [DerivedDataRow]) -> some View {
        GroupedSection(title: title) {
            ForEach(rows) { row in
                HStack(spacing: 12) {
                    if row.isSelectable {
                        Toggle("Select \(row.name)", isOn: Binding(get: { model.selection.contains(row.id) }, set: { on in
                            if on { model.selection.insert(row.id) } else { model.selection.remove(row.id) }
                        })).labelsHidden().toggleStyle(.checkbox).disabled(model.app.cleanupQueue.task(for: row.id) != nil)
                    } else { Image(systemName: "lock").foregroundStyle(.tertiary).frame(width: 18) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.name).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                        Text(row.projectPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Text(row.shortReason).font(.callout).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).help(row.reason)
                    if model.app.cleanupQueue.task(for: row.id) != nil {
                        QueuedItemStatus(queue: model.app.cleanupQueue, resource: row.id)
                    } else if row.isSelectable {
                        StatusChip(words: StatusWords("Ready to delete", .green, symbol: "checkmark.circle"))
                    }
                    SizeText(bytes: row.bytes).frame(width: 85, alignment: .trailing)
                }.contextMenu {
                    Button("Show in Finder") { FolderActions.reveal([URL(fileURLWithPath: row.id)]) }
                    Button("Copy path") { FolderActions.copy([row.id]) }
                }
                if row.id != rows.last?.id { Divider() }
            }
        }
    }
}
