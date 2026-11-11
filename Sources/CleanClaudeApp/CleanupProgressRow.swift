import CleanAppModel
import SwiftUI

struct CleanupProgressRow: View {
    let item: CleanupItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if item.state == .running { ProgressView().controlSize(.small) }
                else { Image(systemName: symbol).foregroundStyle(color) }
            }
            .frame(width: 18)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(item.name).fontWeight(.medium).lineLimit(1).truncationMode(.middle).help(item.name)
                    Spacer(minLength: 10)
                    Text(status).font(.callout).foregroundStyle(color).monospacedDigit()
                }
                if let result = item.result {
                    if !result.detail.isEmpty { Text(result.detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                    ForEach(Array(result.warnings.enumerated()), id: \.offset) { _, warning in
                        Text(warning).font(.callout).foregroundStyle(Palette.orange).textSelection(.enabled)
                    }
                }
            }
        }
        .padding(.vertical, 12)
    }

    private var status: String {
        switch item.state {
        case .waiting: "Waiting"
        case .running: "Cleaning…"
        case .done: item.result?.freedBytes.map { "\(DisplayText.bytes($0)) freed" } ?? "Done · space unavailable"
        case .refused: "Left alone"
        case .failed: "Couldn't clean"
        case .stopped: "Stopped · left alone"
        }
    }
    private var symbol: String {
        switch item.state {
        case .done: "checkmark.circle.fill"
        case .refused, .failed: "exclamationmark.circle.fill"
        case .stopped: "stop.circle"
        default: "clock"
        }
    }
    private var color: Color {
        switch item.state {
        case .done: item.result?.warnings.isEmpty == false ? Palette.orange : Palette.green
        case .refused, .failed: Palette.orange
        case .running: Palette.blue
        default: Palette.grey
        }
    }
}
