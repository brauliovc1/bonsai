import CleanAppModel
import CleanCore
import SwiftUI

struct CompareDiffPane: View {
    @Bindable var model: CompareModel
    let change: Int

    var body: some View {
        VStack(spacing: 0) {
            if let file = model.selectedFile {
                HStack {
                    Text(DiffText.decode(Data(file.path.utf8))).font(.system(.callout, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Menu { CompareFileActions(model: model, file: file) } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).fixedSize()
                }.padding(12)
                HStack {
                    Picker("Layout", selection: $model.sideBySide) {
                        Text("Unified").tag(false); Text("Side by side").tag(true)
                    }.pickerStyle(.segmented).fixedSize()
                    Spacer()
                    Toggle("Ignore whitespace", isOn: $model.ignoresWhitespace).toggleStyle(.checkbox)
                        .onChange(of: model.ignoresWhitespace) { Task { await model.changeWhitespace() } }
                }.font(.callout).padding(.horizontal, 12).padding(.bottom, 10)
                Divider()
                if file.modeChanged { Text("Mode changed: \(file.oldMode ?? "") → \(file.newMode ?? "")").font(.callout).foregroundStyle(.secondary).padding(10) }
                if file.isBinary {
                    EmptyState(systemImage: "doc", headline: "Binary file", line: "\(size(file.oldBytes)) → \(size(file.newBytes)) · A text diff isn't available.")
                } else if model.diffIsCollapsed {
                    EmptyState(systemImage: "doc.text", headline: file.isGenerated ? "Generated file" : "Large file",
                        line: file.isGenerated ? "Generated changes are collapsed to keep the review focused." : "More than 3,000 changed lines or 1 MB. Loading may take a moment.",
                        actionTitle: "Show anyway") { Task { await model.showAnyway() } }
                } else if model.isLoadingDiff { Spacer(); ProgressView("Reading diff…"); Spacer() }
                else if let document = model.document {
                    NativeDiffView(document: document, path: file.path, sideBySide: model.sideBySide, change: change)
                    if !document.hunks.isEmpty {
                        Divider()
                        Button("Show 20 more lines") { Task { await model.showMoreContext() } }.buttonStyle(.link).padding(8)
                    } else { Text("No text changes with these options.").foregroundStyle(.secondary).padding(18) }
                }
            } else {
                EmptyState(systemImage: "doc.text.magnifyingglass", headline: "Pick a file", line: "Select a changed file to read its diff.")
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func size(_ bytes: Int?) -> String { bytes.map { DisplayText.bytes(Int64($0)) } ?? "Size unavailable" }
}
