import CleanAppModel
import CleanCore
import SwiftUI

struct BranchMapPanel: View {
    @Bindable var model: BranchMapModel
    let navigation: NavigationModel
    var worktrees: WorktreesModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button { Task { await model.setOpen(!model.isOpen) } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: model.isOpen ? "chevron.down" : "chevron.right").font(.caption.weight(.semibold))
                        Text(BranchHistoryText.plain(model.collapsedSummary)).font(.callout.weight(.medium)).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).help(model.isOpen ? "Hide branch map" : "Show branch distances and family history")
                if model.isLoading { ProgressView().controlSize(.small) }
            }
            if model.isOpen {
                HStack(spacing: 14) {
                    Picker("View", selection: Binding(get: { model.layout }, set: { value in Task { await model.setLayout(value) } })) {
                        Text("List").tag(BranchMapModel.Layout.list)
                        Text("Timeline").tag(BranchMapModel.Layout.timeline)
                    }.pickerStyle(.segmented).fixedSize()
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
