import CleanAppModel
import CleanCore
import SwiftUI

/// The Worktrees toolbar's filter menu: kind, status, idle at least N days.
struct WorktreesFilterMenu: View {
    @Bindable var model: WorktreesModel

    var body: some View {
        Menu {
            Picker("Kind", selection: $model.kindFilter) {
                Text("Any kind").tag(WorktreeKind?.none)
                ForEach(WorktreeKind.allCases, id: \.self) { kind in
                    Text(kind.rawValue).tag(WorktreeKind?.some(kind))
                }
            }
            Picker("Status", selection: $model.statusFilter) {
                Text("Any status").tag(WorktreesModel.StatusFilter?.none)
                ForEach(WorktreesModel.StatusFilter.allCases) { status in
                    Text(status.title).tag(WorktreesModel.StatusFilter?.some(status))
                }
            }
            Picker("Idle", selection: $model.minimumIdleDays) {
                Text("Any idle time").tag(Int?.none)
                ForEach(WorktreesModel.idleChoices, id: \.self) { days in
                    Text("Idle \(days)+ days").tag(Int?.some(days))
                }
            }
            Divider()
            Button("Clear Filters") { model.clearFilters() }
                .disabled(!model.hasActiveFilters)
        } label: {
            Label(
                "Filter",
                systemImage: model.hasActiveFilters
                    ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
            )
        }
        .help("Filter by kind, status or idle time")
    }
}
