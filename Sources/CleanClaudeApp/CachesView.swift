import CleanAppModel
import CleanCore
import SwiftUI

/// The Tool caches screen (PLAN §4.6): package-manager caches and Cursor's data with their sizes and whether each
/// can be cleaned now. Ready rows have a checkbox; Cursor's live data is shown greyed, never selectable.
struct CachesView: View {
    @Bindable var model: CachesModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    CacheSection(model: model, section: .packages, rows: model.rows(in: .packages))
                    CacheSection(model: model, section: .cursor, rows: model.rows(in: .cursor))
                    ForEach(model.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                    }
                }
                .padding(20)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay {
                if model.report == nil { ProgressView("Looking at the caches…") }
            }
            Divider()
            statusBar
        }
        .navigationTitle("Tool caches")
        .toolbar { toolbar }
        .sheet(isPresented: $model.isShowingCleanSheet, onDismiss: { model.dismissClean() }) {
            CachesCleanSheet(model: model)
        }
        .task { await model.loadIfNeeded() }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if model.isScanning {
                ProgressView().controlSize(.small)
            }
            if let date = model.lastScanAt {
                Text("Scanned \(date, format: .relative(presentation: .named))")
            }
            Spacer()
            Button("Select all ready") { model.selectAllReady() }
                .disabled(model.readyRows.isEmpty)
            Text("\(model.readyRows.count) ready, \(DisplayText.bytes(model.readyBytes))")
            Text("of \(DisplayText.bytes(model.totalBytes))").monospacedDigit()
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
            Button { Task { await model.beginClean() } } label: {
                Label("Clean selected…", systemImage: "trash")
            }
            .help("Clean the selected entries (you confirm first)")
            .disabled(!model.canClean)
        }
    }
}

/// One section: its heading, the column titles, and a row per entry; Cursor's read-only rows come last under
/// their own small heading.
private struct CacheSection: View {
    let model: CachesModel
    let section: ToolCacheEntry.Section
    let rows: [CacheRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title).font(.title3.weight(.semibold))
            if section == .cursor, let line = model.cursorRunningLine {
                Label(line, systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
            }
            if rows.isEmpty {
                Text(model.report == nil ? "Not scanned yet." : "None of these are on this Mac.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    CacheColumns.header
                    Divider()
                    ForEach(rows.filter { !$0.isDisplayOnly }) { row in
                        CacheRowView(model: model, row: row)
                        Divider()
                    }
                    let shownOnly = rows.filter(\.isDisplayOnly)
                    if !shownOnly.isEmpty {
                        Text("Shown only, never cleaned")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.top, 10)
                            .padding(.bottom, 4)
                        ForEach(shownOnly) { row in
                            CacheRowView(model: model, row: row)
                            Divider()
                        }
                    }
                }
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

/// The column widths, shared by the header and the rows.
private enum CacheColumns {
    static let check: CGFloat = 22
    static let name: CGFloat = 210
    static let size: CGFloat = 72
    static let status: CGFloat = 250

    static var header: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: check, height: 1)
            Text("Name").frame(width: name, alignment: .leading)
            Text("Folder").frame(maxWidth: .infinity, alignment: .leading)
            Text("Size").frame(width: size, alignment: .trailing)
            Text("Status").frame(width: status, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

private struct CacheRowView: View {
    let model: CachesModel
    let row: CacheRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Group {
                if row.isDisplayOnly {
                    Image(systemName: "lock").foregroundStyle(.tertiary)
                } else {
                    Toggle("Select \(row.name)", isOn: Binding(
                        get: { model.isSelected(row.id) },
                        set: { model.setSelected(row.id, $0) }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(!row.isSelectable)
                }
            }
            .frame(width: CacheColumns.check)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).fontWeight(row.isDisplayOnly ? .regular : .medium)
                if let kept = row.keptText {
                    Text(kept).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .frame(width: CacheColumns.name, alignment: .leading)
            Text(row.folderText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(row.folderHelp)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.sizeText)
                .monospacedDigit()
                .frame(width: CacheColumns.size, alignment: .trailing)
            CacheStatusCell(row: row)
                .frame(width: CacheColumns.status, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .opacity(row.isDisplayOnly ? 0.6 : 1)
        .help(row.note)
    }
}

/// "Ready" as a badge; a running tool in orange; anything else as a secondary line with the full text as the
/// tooltip.
private struct CacheStatusCell: View {
    let row: CacheRow

    var body: some View {
        switch row.tone {
        case .ready:
            Badge(text: row.statusText, color: .green)
        case .waiting:
            Label(row.statusText, systemImage: "hourglass")
                .foregroundStyle(.orange)
                .lineLimit(2)
        case .refused:
            Label(row.statusText, systemImage: "nosign")
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .help(row.statusText)
        case .empty, .displayOnly:
            Text(row.statusText).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}
