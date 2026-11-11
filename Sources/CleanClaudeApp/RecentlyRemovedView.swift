import CleanAppModel
import SwiftUI

struct RecentlyRemovedView: View {
    @Bindable var model: RemovalsModel
    @State private var sort: ContentSort = .activity
    private var days: [Date] { Set(model.rows.map { Calendar.current.startOfDay(for: $0.date) }).sorted(by: >) }
    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Recently removed", subtitle: "Restore kept worktrees or put downloads back while they remain in Trash.") {
                Button("Refresh") { model.app.reloadLog() }
            }.padding(20)
            if let error = model.logError { ProblemBanner(text: error) }
            ContentSortBar(selection: $sort, showsActivity: true)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if model.rows.isEmpty, model.logError == nil {
                        EmptyState(systemImage: "clock.arrow.circlepath", headline: "Nothing removed yet", line: "Your cleanup history and restore actions will appear here.")
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(days, id: \.self) { day in
                        GroupedSection(title: day.formatted(.dateTime.weekday(.wide).month(.wide).day())) {
                            let rows = rows(on: day)
                            ForEach(rows) { row in
                                RemovalHistoryRow(model: model, row: row)
                                if row.id != rows.last?.id { Divider() }
                            }
                        }
                    }
                }.padding(20)
            }
            if let message = model.message {
                SelectionBar(text: message.text) { Button("Dismiss") { model.message = nil } }
                    .foregroundStyle(message.isError ? Palette.orange : Palette.green)
            }
        }.navigationTitle("Recently removed")
    }
    private func rows(on day: Date) -> [RemovalLogRow] {
        model.rows.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }.sorted {
            if sort == .size, $0.freedSortKey != $1.freedSortKey { return $0.freedSortKey > $1.freedSortKey }
            if sort == .name, $0.path != $1.path { return $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            return $0.date > $1.date
        }
    }
}
