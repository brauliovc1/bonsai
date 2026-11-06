import CleanAppModel
import SwiftUI

/// "123.4 GB free of 460.4 GB" with a used-space bar and percentage.
struct DiskSummaryView: View {
    let disk: DiskSpaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(DisplayText.bytes(disk.freeBytes)) free")
                    .font(.headline)
                    .monospacedDigit()
                Spacer()
                if let used = disk.usedFraction {
                    Text("\(used, format: .percent.precision(.fractionLength(0))) used")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            ProgressView(value: disk.usedFraction ?? 0)
                .tint((disk.usedFraction ?? 0) > 0.9 ? .red : .accentColor)
            Text("of \(DisplayText.bytes(disk.totalBytes)) on the volume of \(disk.folder?.path ?? "–")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
