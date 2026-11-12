import CleanAppModel
import CleanCore
import SwiftUI

struct BranchMapPanel: View {
    @Bindable var model: BranchMapModel
    let navigation: NavigationModel
    var worktrees: WorktreesModel?
    var focused = false
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if focused {
                HStack {
                    Button { model.isFocused = false; Task { await model.setOpen(false) } } label: { Label("Back to changes", systemImage: "chevron.left") }
                    Spacer()
                    Text("Branch map").font(.headline)
                }
            } else {
                Button { Task { await model.setOpen(!model.isOpen) } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: model.isOpen ? "chevron.down" : "chevron.right").font(.caption)
                        Text("Branch map").fontWeight(.medium)
                        if model.collapsedSummary != "Branch map" {
                            Text(BranchHistoryText.plain(model.collapsedSummary)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                        }
                        Spacer(minLength: 0)
                        if model.isLoading { ProgressView().controlSize(.mini) }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(model.isOpen ? "Hide branch map" : "Show branch map")
            }
            if model.isOpen || focused {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { layout; searchField; Spacer(minLength: 0); actions }
                    VStack(spacing: 8) {
                        HStack { layout; Spacer(minLength: 0); actions }
                        searchField
                    }
                }
                HStack(spacing: 10) {
                    Picker("Sort branches", selection: $model.sort) {
                        Text("Closest to base").tag(BranchMapLayout.Sort.closest)
                        Text("Most recent").tag(BranchMapLayout.Sort.recent)
                        Text("Name").tag(BranchMapLayout.Sort.name)
                    }.labelsHidden().fixedSize()
                    Spacer(minLength: 0)
                    Toggle("Remote branches", isOn: Binding(get: { model.includesRemotes }, set: { value in Task { await model.setIncludesRemotes(value) } }))
                        .toggleStyle(.checkbox).fixedSize()
                }.font(.callout).controlSize(.small)
                if let problem = model.problem { ProblemBanner(text: BranchHistoryText.plain(problem)) }
                if model.layout == .timeline { BranchTimelineAxis(model: model) }
                else { BranchMapListAxis() }
                ScrollViewReader { proxy in
                    ScrollView {
                        if model.layout == .list { BranchMapList(model: model, search: search) }
                        else { BranchMapTimeline(model: model, search: search) }
                    }
                    .onAppear { if let ref = model.selectedRef { proxy.scrollTo(ref, anchor: .center) } }
                    .onChange(of: model.selectedRef) { _, ref in if let ref { proxy.scrollTo(ref, anchor: .center) } }
                    .onChange(of: model.rows.map(\.ref)) { _, _ in if let ref = model.selectedRef { proxy.scrollTo(ref, anchor: .center) } }
                }
                .frame(minHeight: focused ? 100 : 90, maxHeight: focused ? .infinity : 180)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, focused ? 12 : 8)
        .popover(isPresented: $model.showsHistory) {
            BranchHistoryCard(model: model) { path in
                worktrees?.revealWorktree(path); model.showsHistory = false; navigation.show(.worktrees)
            }
        }
    }
    private var layout: some View {
        Picker("Branch map view", selection: Binding(get: { model.layout }, set: { value in Task { await model.setLayout(value) } })) {
            Text("List").tag(BranchMapModel.Layout.list)
            Text("Timeline").tag(BranchMapModel.Layout.timeline)
        }.labelsHidden().pickerStyle(.segmented).fixedSize()
    }
    private var searchField: some View {
        TextField("Find branch", text: $search).textFieldStyle(.roundedBorder).frame(minWidth: 110, maxWidth: 220)
    }
    private var actions: some View {
        HStack(spacing: 8) {
            Button("History…") { Task { await model.requestHistory() } }.disabled(model.selectedRef == nil)
            if !focused { Button("Expand map") { model.isFocused = true } }
        }.fixedSize()
    }
}
