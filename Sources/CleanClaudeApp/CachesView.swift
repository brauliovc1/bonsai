import CleanAppModel
import CleanCore
import SwiftUI

struct CachesView: View {
    @Bindable var model: CachesModel
    @State private var sort: ContentSort = .size
    var body: some View {
        VStack(spacing: 0) {
            CleanupPageHeader(subtitle: "Downloaded packages and temporary tool data. Each tool keeps its own safety checks.")
            HStack {
                ContentSortBar(selection: $sort)
                Button("Select all ready") { model.selectAllReady() }.disabled(model.readyRows.isEmpty)
            }.padding(.trailing, 20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if model.report == nil { ProgressView("Looking at the caches…").frame(maxWidth: .infinity).padding(30) }
                    else if model.allRows.isEmpty {
                        EmptyState(systemImage: "shippingbox", headline: "No tool caches to clean", line: "Caches appear here when your tools download packages.")
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(model.allRows.isEmpty ? [] : [ToolCacheEntry.Section.packages, .cursor], id: \.self) { section in
                        GroupedSection(title: section.title) {
                            if section == .cursor, let line = model.cursorRunningLine {
                                Label(line, systemImage: "info.circle").foregroundStyle(Palette.blue)
                            }
                            let rows = sorted(model.rows(in: section))
                            if rows.isEmpty { NothingLine(text: "No caches found here.") }
                            ForEach(rows) { row in
                                CacheListRow(model: model, row: row)
                                if row.id != rows.last?.id { Divider() }
                            }
                        }
                    }
                    ForEach(model.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(Palette.orange)
                    }
                }.padding(20)
            }
            if !model.selectedRows.isEmpty {
                SelectionBar(text: "\(model.selectedRows.count) selected · \(CleanupPresentation.estimate(model.selectedRows.map(\.bytes)))") {
                    Button("Clear") { model.selection.removeAll() }
                    Button("Clean selected…") { Task { await model.beginClean() } }.disabled(!model.canClean)
                }
            } else {
                SelectionBar(text: "Select caches to review cleanup") { EmptyView() }
            }
        }
        .navigationTitle("Tool caches")
        .toolbar {
            Button { Task { await model.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .keyboardShortcut("r").disabled(model.isScanning)
        }
        .sheet(isPresented: $model.isShowingCleanSheet, onDismiss: { model.dismissClean() }) { CachesCleanSheet(model: model) }
        .task { await model.loadIfNeeded() }
    }
    private func sorted(_ rows: [CacheRow]) -> [CacheRow] {
        rows.sorted {
            if $0.isDisplayOnly != $1.isDisplayOnly { return !$0.isDisplayOnly }
            if sort == .size, $0.bytes != $1.bytes { return ($0.bytes ?? -1) > ($1.bytes ?? -1) }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
