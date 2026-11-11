import CleanAppModel
import CleanCore
import SwiftUI

struct BranchMapPanel: View {
    @Bindable var model: BranchMapModel
    let navigation: NavigationModel
    var worktrees: WorktreesModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Branch map").font(.headline)
                    Text(BranchHistoryText.plain(model.collapsedSummary))
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if model.isLoading { ProgressView().controlSize(.small) }
                if model.isOpen {
                    Button("Hide branch map") { Task { await model.setOpen(false) } }
                } else {
                    Button("Show branch map") { Task { await model.setOpen(true) } }
                        .help("See branch distances, family history and merge status.")
                    Button("Timeline") {
                        Task {
                            await model.setLayout(.timeline)
                            await model.setOpen(true)
                        }
                    }
                    .accessibilityLabel("Show branch map timeline")
                    .help("See when branches forked and their commits on a timeline.")
                }
            }.controlSize(.small)
            if model.isOpen {
                HStack(spacing: 14) {
                    Picker("View", selection: Binding(get: { model.layout }, set: { value in Task { await model.setLayout(value) } })) {
                        Text("List").tag(BranchMapModel.Layout.list)
                        Text("Timeline").tag(BranchMapModel.Layout.timeline)
                    }.pickerStyle(.segmented).fixedSize().accessibilityLabel("Branch map view")
                    Picker("Sort", selection: $model.sort) {
                        Text("Closest to base").tag(BranchMapLayout.Sort.closest)
                        Text("Most recent").tag(BranchMapLayout.Sort.recent)
                        Text("Name").tag(BranchMapLayout.Sort.name)
                    }.fixedSize()
                    Spacer(minLength: 8)
                    Toggle("Remote branches", isOn: Binding(get: { model.includesRemotes }, set: { value in Task { await model.setIncludesRemotes(value) } }))
                        .toggleStyle(.checkbox).fixedSize()
                }.font(.callout)
                if let problem = model.problem { ProblemBanner(text: BranchHistoryText.plain(problem)) }
                ScrollView {
                    if model.layout == .list { BranchMapList(model: model) }
                    else { BranchMapTimeline(model: model) }
                }.frame(minHeight: 90, maxHeight: 220)
            }
        }
        .padding(.horizontal, 18).padding(.bottom, 12)
        .popover(isPresented: $model.showsHistory) {
            BranchHistoryCard(model: model) { path in
                worktrees?.revealWorktree(path)
                model.showsHistory = false
                navigation.show(.worktrees)
            }
        }
    }
}
