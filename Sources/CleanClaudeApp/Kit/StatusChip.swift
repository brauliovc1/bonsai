import CleanAppModel
import SwiftUI

/// A status in a soft tint of its color, with an optional SF Symbol: "Ready to remove", "3 unsaved changes",
/// "Open in node" (PLAN §8.4). Sentence case, never all caps.
struct StatusChip: View {
    let words: StatusWords
    var wraps = false

    var body: some View {
        HStack(spacing: 4) {
            if let symbol = words.symbol {
                Image(systemName: symbol).imageScale(.small)
            }
            Text(words.text)
        }
        .font(.callout.weight(.medium))
        .lineLimit(wraps ? nil : 1)
        .foregroundStyle(Palette.color(words.tone))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Palette.tint(words.tone), in: Capsule())
        .fixedSize(horizontal: !wraps, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Status chips") {
    VStack(alignment: .leading, spacing: 8) {
        StatusChip(words: StatusWords("Ready · auto clean", .green, symbol: "checkmark.circle.fill"))
        StatusChip(words: StatusWords("Ready to remove", .green, symbol: "checkmark.circle"))
        StatusChip(words: StatusWords("3 unsaved changes", .orange, symbol: "pencil.circle"))
        StatusChip(words: StatusWords("Open in node", .blue, symbol: "macwindow"))
        StatusChip(words: StatusWords("Locked", .grey, symbol: "lock"))
    }
    .padding()
}
