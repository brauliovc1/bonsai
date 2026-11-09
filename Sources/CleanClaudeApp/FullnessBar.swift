import CleanAppModel
import SwiftUI

/// How full the disk is, coloured like the menu-bar label: the accent colour, orange below the low-space
/// warning, red under half of it. Drawn by hand (not a ProgressView), so the colour shows in any window state.
struct FullnessBar: View {
    let fraction: Double
    let level: MenuBarModel.Level

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel("Disk used")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }

    private var color: Color {
        switch level {
        case .low: .orange
        case .veryLow: .red
        case .normal, .unknown: .accentColor
        }
    }
}
