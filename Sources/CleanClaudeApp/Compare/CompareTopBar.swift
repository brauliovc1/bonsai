import CleanAppModel
import CleanCore
import SwiftUI

struct CompareTopBar: View {
    @Bindable var model: CompareModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ComparePicker(title: "Repo", value: model.repository.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Choose repo",
                    options: model.repositories.map { ($0, URL(fileURLWithPath: $0).lastPathComponent) }) { repo in
                    Task { await model.configure(repo: repo) }
                }.frame(minWidth: 120, maxWidth: 200)
                ComparePicker(title: "Base", value: model.base.isEmpty ? "Choose base" : model.base, options: refs) { ref in
                    model.base = ref; Task { await model.refresh() }
                }.frame(maxWidth: .infinity)
                Button { Task { await model.swap() } } label: { Image(systemName: "arrow.left.arrow.right") }
                    .help("Swap base and compare")
                ComparePicker(title: "Compare", value: model.compare.label, options: compareOptions) { value in
                    model.compare = value.hasPrefix("worktree:") ? .worktree(String(value.dropFirst(9))) : .ref(value)
                    Task { await model.refresh() }
                }.frame(maxWidth: .infinity)
                Button { Task { await model.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(model.repository == nil)
            }
            Text(model.fetchText).font(.callout).foregroundStyle(.secondary)
        }.padding(18)
    }

    private var refs: [(String, String)] { model.catalog?.refs.map { ($0.name, $0.name + ($0.kind == .tag ? " · Tag" : "")) } ?? [] }
    private var compareOptions: [(String, String)] {
        refs + (model.catalog?.worktrees.filter { !$0.isBare && !$0.isPrunable }.map {
            ("worktree:" + $0.path, ($0.branch ?? "Detached") + " · " + $0.url.lastPathComponent + " (worktree)")
        } ?? [])
    }
}

/// A searchable native popover picker. Values stay strings; no branch name becomes executable text.
struct ComparePicker: View {
    let title: String
    let value: String
    let options: [(String, String)]
    let pick: (String) -> Void
    @State private var isOpen = false
    @State private var search = ""

    var body: some View {
        Button { search = ""; isOpen = true } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(value).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down").font(.caption)
                }
            }.padding(.horizontal, 10).padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.stroke))
        .accessibilityLabel("\(title): \(value)")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                TextField("Find \(title.lowercased())", text: $search).textFieldStyle(.roundedBorder).padding(10)
                List {
                    ForEach(options.filter { search.isEmpty || $0.1.localizedCaseInsensitiveContains(search) }, id: \.0) { item in
                        Button { pick(item.0); isOpen = false } label: { Text(item.1).frame(maxWidth: .infinity, alignment: .leading) }
                            .buttonStyle(.plain).padding(.vertical, 4)
                    }
                }
            }.frame(width: 350, height: 330)
        }
    }
}
