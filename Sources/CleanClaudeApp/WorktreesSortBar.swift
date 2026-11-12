import CleanAppModel
import SwiftUI

/// The slim bar at the top of the Worktrees list: "Sort: Size ▾ · Group by repo". In the content area, not the
/// toolbar, so the toolbar keeps the same structure on every screen and width.
struct WorktreesSortBar: View {
    @Bindable var model: WorktreesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                filter.labelsHidden().pickerStyle(.segmented).fixedSize()
                filter.pickerStyle(.menu)
            }
            HStack(spacing: 8) {
                Text("Sort:").foregroundStyle(.secondary)
                Picker("Sort", selection: $model.sortKey) {
                    ForEach(WorktreesModel.SortKey.allCases) { key in Text(key.title).tag(key) }
                }.labelsHidden().pickerStyle(.menu).fixedSize()
                Text("·").foregroundStyle(.tertiary)
                Toggle("Group by repo", isOn: $model.groupsByRepo).toggleStyle(.checkbox)
                Spacer(minLength: 0)
            }.font(.callout).controlSize(.small)
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var filter: some View {
        Picker("Show worktrees", selection: $model.filter) {
            ForEach(WorktreesModel.Filter.allCases) { filter in Text(model.title(filter)).tag(filter) }
        }.help("Worktrees that can be removed, those with local work that needs you, or all of them")
    }
}
