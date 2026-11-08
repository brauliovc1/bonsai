import CleanAppModel
import SwiftUI

/// The Overview: free space, what can be reclaimed in each category with a button to the screen that does
/// it, the auto-mode placeholder, and the last scan with Refresh.
struct OverviewView: View {
    let model: OverviewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let problem = model.app.problem {
                    ProblemBanner(text: problem)
                }
                FreeSpaceCard(disk: model.disk)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reclaimable").font(.headline)
                    VStack(spacing: 0) {
                        ForEach(model.rows) { row in
                            OverviewRowView(row: row) { model.jump(to: row.kind) }
                            Divider()
                        }
                    }
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    Text("Sizes are estimates. What a cleanup really frees is measured from the disk afterwards.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Image(systemName: "clock.badge.checkmark").foregroundStyle(.secondary)
                    Text(OverviewModel.autoModeText)
                    Spacer()
                }
                .padding(12)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                HStack(spacing: 10) {
                    if model.isRefreshing {
                        ProgressView().controlSize(.small)
                    }
                    ScanTimeText(app: model.app)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") { Task { await model.refresh() } }
                        .disabled(model.isRefreshing)
                }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Overview")
        .task { await model.loadIfNeeded() }
    }
}

/// "123.4 GB free" large, the used-space bar with its percentage, and which disk it is.
private struct FreeSpaceCard: View {
    let disk: DiskSpaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(DisplayText.bytes(disk.freeBytes)) free")
                .font(.system(size: 38, weight: .semibold))
                .monospacedDigit()
            ProgressView(value: disk.usedFraction ?? 0)
                .tint((disk.usedFraction ?? 0) > 0.9 ? .red : .accentColor)
            HStack {
                if let used = disk.usedFraction {
                    Text("\(used, format: .percent.precision(.fractionLength(0))) used")
                        .monospacedDigit()
                }
                Spacer()
                Text("of \(DisplayText.bytes(disk.totalBytes))" + (disk.volumeName.map { " on \($0)" } ?? ""))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}

/// One category: what it is, how many, how big, and a button to its screen.
private struct OverviewRowView: View {
    let row: OverviewRow
    let jump: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.sizeText)
                .monospacedDigit()
                .fontWeight(.semibold)
            Button(row.buttonTitle, action: jump)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
