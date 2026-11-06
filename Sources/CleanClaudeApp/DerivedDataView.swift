import CleanAppModel
import SwiftUI

/// The Xcode DerivedData screen: every folder of the root with its state and size. Only orphaned folders
/// (their project is gone) can be selected and deleted; the rest is read-only with a one-line reason. A
/// refused root is an error banner with no delete button.
struct DerivedDataView: View {
    @Bindable var model: DerivedDataModel

    var body: some View {
        VStack(spacing: 0) {
            if let refusal = model.refusal {
                ProblemBanner(text: "The DerivedData folder is refused: \(refusal) Nothing can be deleted.")
            }
            table
            Divider()
            statusBar
        }
        .navigationTitle("Xcode DerivedData")
        .toolbar { toolbar }
        .sheet(isPresented: $model.isShowingDeleteSheet, onDismiss: { model.dismissDelete() }) {
            DerivedDataDeleteSheet(model: model)
        }
        .task { await model.loadIfNeeded() }
    }

    private var table: some View {
        Table(model.rows, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn("Folder", value: \.name) { row in
                Text(row.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(row.id)
            }
            .width(min: 120, ideal: 190)
            TableColumn("Project", value: \.projectPath) { row in
                Text(row.projectPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(row.projectPath)
            }
            .width(min: 120, ideal: 210)
            TableColumn("State") { row in
                DerivedDataStateCell(row: row)
            }
            .width(min: 200, ideal: 360)
            TableColumn("Size", value: \.sizeSortKey) { row in
                Text(row.sizeText).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 64, ideal: 78)
        }
        .contextMenu(forSelectionType: DerivedDataRow.ID.self) { ids in
            let rows = model.rows.filter { ids.contains($0.id) }
            if !rows.isEmpty {
                Button("Reveal in Finder") { FolderActions.reveal(rows.map { URL(fileURLWithPath: $0.id, isDirectory: true) }) }
                Button(rows.count == 1 ? "Copy Path" : "Copy Paths") { FolderActions.copy(rows.map(\.id)) }
            }
            if rows.contains(where: \.isSelectable) {
                Divider()
                Button("Delete orphaned…") { Task { await model.beginDelete(ids) } }
                    .disabled(model.refusal != nil || model.app.isCleaningUp)
            }
        }
        .overlay {
            if model.report == nil {
                ProgressView("Reading DerivedData…")
            } else if model.rootMissing {
                ContentUnavailableView(
                    "No DerivedData folder",
                    systemImage: "hammer",
                    description: Text("\(model.root ?? "The folder") doesn't exist: Xcode hasn't built anything yet.")
                )
            } else if model.allRows.isEmpty, model.refusal == nil {
                ContentUnavailableView("DerivedData is empty", systemImage: "hammer")
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if model.isScanning {
                ProgressView().controlSize(.small)
            }
            if let date = model.lastScanAt {
                Text("Scanned \(date, format: .relative(presentation: .named))")
            }
            if let root = model.root {
                Text(root)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(root)
            }
            if !model.warnings.isEmpty {
                Text("\(model.warnings.count) \(model.warnings.count == 1 ? "warning" : "warnings")")
                    .help(model.warnings.joined(separator: "\n"))
            }
            Spacer()
            Text("\(model.orphanRows.count) orphaned, \(DisplayText.bytes(model.orphanBytes))")
            Text("of \(DisplayText.bytes(model.totalBytes))")
                .monospacedDigit()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { Task { await model.refresh() } } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Scan again")
            .disabled(model.isScanning)
            Button { Task { await model.beginDelete() } } label: {
                Label("Delete orphaned…", systemImage: "trash")
            }
            .help("Delete the selected orphaned folders (you confirm first)")
            .disabled(!model.canDelete)
        }
    }
}

/// The State cell: a badge and the one line that says why the row is read-only (or deletable).
private struct DerivedDataStateCell: View {
    let row: DerivedDataRow

    var body: some View {
        HStack(spacing: 6) {
            Badge(text: row.stateText, color: color)
            Text(row.shortReason)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .help(row.reason)
    }

    private var color: Color {
        switch row.tone {
        case .orphaned: .red
        case .live: .green
        case .internalOrCache: .secondary
        case .warning: .orange
        }
    }
}
