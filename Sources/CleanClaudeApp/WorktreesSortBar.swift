import CleanAppModel
import SwiftUI

/// The slim bar at the top of the Worktrees list: "Sort: Size ▾ · Group by repo". In the content area, not the
/// toolbar, so the toolbar keeps the same structure on every screen and width.
struct WorktreesSortBar: View {
    @Bindable var model: WorktreesModel

    var body: some View {
        HStack(spacing: 8) {
            Text("Sort:").foregroundStyle(.secondary)
            Picker("Sort", selection: $model.sortKey) {
                ForEach(WorktreesModel.SortKey.allCases) { key in
                    Text(key.title).tag(key)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .help("Size: largest first. Last activity: oldest first. Name: by repo and branch.")
            Text("·").foregroundStyle(.tertiary)
            Toggle("Group by repo", isOn: $model.groupsByRepo)
                .toggleStyle(.checkbox)
                .help("Off: one list across all repos, sorted the same way, each row with its repo's name")
            Spacer(minLength: 0)
        }
        .font(.callout)
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }
}
