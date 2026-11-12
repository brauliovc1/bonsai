import CleanAppModel
import CleanCore
import SwiftUI

struct CompareFilesView: View {
    @Bindable var model: CompareModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Filter files", text: $model.filter).textFieldStyle(.roundedBorder)
                Toggle(isOn: $model.flatList) { Image(systemName: "list.bullet") }.toggleStyle(.button).help("Flat file list")
            }.padding(10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(entries, id: \.id) { entry in
                        if let folder = entry.folder {
                            Button { toggleFolder(folder) } label: {
                                Label(URL(fileURLWithPath: folder).lastPathComponent, systemImage: model.collapsedFolders.contains(folder) ? "chevron.right" : "chevron.down")
                                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                            }.buttonStyle(.plain).padding(.horizontal, 12).padding(.leading, CGFloat(min(5, folder.split(separator: "/").count - 1)) * 10)
                        } else if let file = entry.file { fileRow(file).padding(.leading, model.flatList ? 0 : CGFloat(min(5, file.path.split(separator: "/").count - 1)) * 10) }
                    }
                    if entries.isEmpty, !model.filter.isEmpty {
                        EmptyState(systemImage: "magnifyingglass", headline: "No matching files", line: "Try another file name.", actionTitle: "Clear filter") { model.filter = "" }
                    }
                    if model.generatedCount > 0 {
                        Button { model.showsGenerated.toggle() } label: {
                            Label("Generated files (\(model.generatedCount))", systemImage: model.showsGenerated ? "chevron.down" : "chevron.right")
                                .font(.callout).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        }.buttonStyle(.plain)
                    }
                }.padding(.vertical, 4)
            }
            Spacer(minLength: 0)
        }
    }

    private func fileRow(_ file: CompareFile) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Button { model.toggleViewed(file.path) } label: {
                Image(systemName: model.isViewed(file.path) ? "checkmark.square.fill" : "square").foregroundStyle(.secondary)
            }.buttonStyle(.borderless).help("Mark as viewed")
            Button { Task { await model.selectFile(file.path) } } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(DiffText.decode(Data((model.flatList ? file.path : URL(fileURLWithPath: file.path).lastPathComponent).utf8))).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 2)
                        if file.isBinary { Text("Binary").font(.caption).foregroundStyle(.secondary) }
                        else {
                            Text("+\(file.additions)").foregroundStyle(Palette.green)
                            Text("−\(file.deletions)").foregroundStyle(Palette.red)
                        }
                    }.font(.callout).monospacedDigit()
                    HStack(spacing: 4) {
                        Text(status(file)).lineLimit(1).truncationMode(.middle)
                        if file.notCommitted { Text("· Not committed").foregroundStyle(Palette.orange) }
                    }.font(.caption).foregroundStyle(.secondary)
                    if file.additions + file.deletions > 0 {
                        GeometryReader { geometry in
                            HStack(spacing: 1) {
                                Palette.green.frame(width: max(2, geometry.size.width * Double(file.additions) / Double(file.additions + file.deletions)))
                                Palette.red
                            }
                        }.frame(width: 52, height: 3).clipShape(Capsule())
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
        }.padding(.horizontal, 10).padding(.vertical, 9)
            .background(model.selectedPath == file.path ? Palette.tint(.blue) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 4)
            .contextMenu { CompareFileActions(model: model, file: file) }
    }

    private func status(_ file: CompareFile) -> String {
        if file.isGenerated { return "Generated · \(file.status.rawValue.capitalized)" }
        if let old = file.oldPath { return "\(file.status == .copied ? "Copied" : "Renamed") from \(DiffText.decode(Data(old.utf8)))" }
        return file.status.rawValue.capitalized + (file.modeChanged ? " · Mode changed" : "")
    }
    private func toggleFolder(_ folder: String) {
        if !model.collapsedFolders.insert(folder).inserted { model.collapsedFolders.remove(folder) }
    }
    private struct Entry { let id: String; var folder: String?; var file: CompareFile? }
    private var entries: [Entry] {
        var entries: [Entry] = []; var seen: Set<String> = []
        for file in model.files where (model.filter.isEmpty || file.path.localizedCaseInsensitiveContains(model.filter))
            && (model.showsGenerated || !file.isGenerated || !model.filter.isEmpty) {
            if !model.flatList {
                let parts = file.path.split(separator: "/").dropLast()
                var folder = ""
                for part in parts {
                    folder += (folder.isEmpty ? "" : "/") + part
                    if seen.insert(folder).inserted { entries.append(Entry(id: "folder:" + folder, folder: folder)) }
                    if model.collapsedFolders.contains(folder) { break }
                }
            }
            if model.flatList || !model.collapsedFolders.contains(where: { file.path.hasPrefix($0 + "/") }) {
                entries.append(Entry(id: file.path, file: file))
            }
        }
        return entries
    }
}
