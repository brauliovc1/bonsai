import CleanAppModel
import SwiftUI

/// "23.0 GB free of 460 GB (95% used)", the used-space bar (orange below the low-space warning, red under
/// half of it, like the menu-bar label), and which disk it is.
struct DiskSummaryView: View {
    let disk: DiskSpaceModel
    let level: MenuBarModel.Level

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(FreeSpaceText.summary(free: disk.freeBytes, total: disk.totalBytes))
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            ProgressView(value: disk.usedFraction ?? 0)
                .tint(tint)
            if let volume = disk.volumeName {
                Text(volume)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var tint: Color {
        switch level {
        case .low: .orange
        case .veryLow: .red
        case .normal, .unknown: .accentColor
        }
    }
}
