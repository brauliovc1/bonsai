import CleanAppModel
import SwiftUI

/// Free space as one big number ("19.2 GB free", orange below the low-space warning and red under half of
/// it, like the menu-bar label) with the disk's size beside it, the used-space bar, and under the bar the
/// disk's name and how full it is ("96% used", or "Low on space").
struct DiskSummaryView: View {
    let disk: DiskSpaceModel
    let level: MenuBarModel.Level

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(DisplayText.bytes(disk.freeBytes))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                if disk.freeBytes != nil {
                    Text("free").foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let total = disk.totalBytes {
                    Text("of \(FreeSpaceText.label(total))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            FullnessBar(fraction: disk.usedFraction ?? 0, level: level)
                .padding(.top, 6)
            HStack {
                Text(disk.volumeName ?? "")
                    .foregroundStyle(.secondary)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(fullness)
                    .foregroundStyle(isLow ? tint : .secondary)
                    .monospacedDigit()
            }
            .font(.caption)
            .lineLimit(1)
            .padding(.top, 6)
        }
        .help(FreeSpaceText.summary(free: disk.freeBytes, total: disk.totalBytes))
    }

    private var isLow: Bool { level == .low || level == .veryLow }

    private var fullness: String {
        if isLow { return "Low on space" }
        guard let used = disk.usedFraction else { return "" }
        return "\(Int((used * 100).rounded()))% used"
    }

    private var tint: Color {
        switch level {
        case .low: .orange
        case .veryLow: .red
        case .normal, .unknown: .primary
        }
    }
}
