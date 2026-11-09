import CleanAppModel
import SwiftUI

/// The Overview's bar: used space (accent, orange when low, red when very low), the part of it Bonsai can free
/// (green, at the end of used, next to free) and free space; a legend under it. Drawn by hand so the colors show
/// in an inactive window too.
struct SpaceBar: View {
    let space: SpaceBreakdown
    let level: MenuBarModel.Level

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let width = proxy.size.width
                HStack(spacing: 0) {
                    Rectangle().fill(Palette.level(level))
                        .frame(width: width * space.usedFraction)
                    Rectangle().fill(Palette.green)
                        .frame(width: width * space.canFreeFraction)
                    Rectangle().fill(.quaternary)
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)
            .accessibilityElement()
            .accessibilityLabel("Disk")
            .accessibilityValue("\(space.usedText), \(space.canFreeText), \(space.freeText)")
            HStack(spacing: 18) {
                LegendItem(color: Palette.level(level), text: space.usedText)
                if space.canFreeBytes > 0 {
                    LegendItem(color: Palette.green, text: space.canFreeText)
                }
                LegendItem(color: Color.primary.opacity(0.15), text: space.freeText)
                Spacer(minLength: 0)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}

/// A colored dot and its words.
private struct LegendItem: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).monospacedDigit().lineLimit(1)
        }
    }
}
