import CleanAppModel
import SwiftUI

/// A size as an estimate: tabular digits, "–" when unknown, and "Measuring…" with a small spinner while the
/// folder is being measured again. The tooltip says it is an estimate.
struct SizeText: View {
    let bytes: Int64?
    var isMeasuring = false
    var isEstimate = true
    var hasUnknownParts = false

    var body: some View {
        Group {
            if isMeasuring {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Measuring…")
                }
                .foregroundStyle(.secondary)
            } else {
                Text(DisplayText.bytes(bytes) + (hasUnknownParts ? "+" : ""))
                    .monospacedDigit()
                    .foregroundStyle(bytes == nil ? .secondary : .primary)
            }
        }
        .lineLimit(1)
        .help(isMeasuring ? "Measuring the folder again after a cleanup" : (isEstimate ? Self.estimateHelp : "Space freed, measured from the disk after cleanup."))
    }

    static let estimateHelp = "An estimate. What a cleanup really frees is measured from the disk afterwards."
}

#Preview("Sizes") {
    VStack(alignment: .trailing, spacing: 8) {
        SizeText(bytes: 3_700_000_000)
        SizeText(bytes: nil)
        SizeText(bytes: 120_000_000, isMeasuring: true)
    }
    .padding()
}
