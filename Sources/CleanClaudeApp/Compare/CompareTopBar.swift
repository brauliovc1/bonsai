import CleanAppModel
import CleanCore
import SwiftUI

struct CompareTopBar: View {
    @Bindable var model: CompareModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.repository == nil {
                repository.frame(maxWidth: 360)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        repository.frame(width: 170)
                        branches.frame(minWidth: 390)
                        refresh
                    }
                    VStack(spacing: 8) {
                        HStack { repository; refresh }
                        branches
                    }
                }
                Text(model.fetchText).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var repository: some View {
        ComparePicker(title: "Repository", value: model.repository.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Choose repository",
            options: model.repositories.map { ($0, URL(fileURLWithPath: $0).lastPathComponent) }) { repo in
            Task { await model.configure(repo: repo) }
        }
    }
    private var branches: some View {
        HStack(spacing: 8) {
            ComparePicker(title: "Base", value: model.base.isEmpty ? "Choose base" : refLabel(model.base), options: refs) { ref in
                model.base = ref; Task { await model.refresh() }
            }
            Button { Task { await model.swap() } } label: { Image(systemName: "arrow.left.arrow.right") }
                .help("Swap base and compare").accessibilityLabel("Swap base and compare")
                .disabled(refs.isEmpty || model.isLoading)
            ComparePicker(title: "Compare", value: compareLabel, options: compareOptions) { value in
                model.compare = value.hasPrefix("worktree:") ? .worktree(String(value.dropFirst(9))) : .ref(value)
                Task { await model.refresh() }
            }
        }
    }
    private var refresh: some View {
        Button { Task { await model.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            .fixedSize().disabled(model.isLoading)
    }

    private var refs: [(String, String)] { model.catalog?.refs.map { ($0.fullName, $0.name + ($0.kind == .tag ? " · Tag" : "")) } ?? [] }
    private func refLabel(_ name: String) -> String { model.catalog?.refs.first { $0.fullName == name }?.name ?? name }
    private var compareLabel: String {
        if case .ref(let name) = model.compare { return refLabel(name) }
        return model.compare.label
    }
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
        .disabled(options.isEmpty)
        .help(value)
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
