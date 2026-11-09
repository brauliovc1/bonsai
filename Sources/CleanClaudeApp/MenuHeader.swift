import CleanAppModel
import SwiftUI

/// The menu window's top line: the bonsai mark and the app's name, a "Test mode" tag while
/// CLEAN_CLAUDE_SCAN_ROOTS is set (the folders it scans are in its tooltip), and Refresh, which turns into a
/// spinner while a scan runs.
struct MenuHeader: View {
    let app: AppModel
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            BonsaiMark()
                .frame(width: 18, height: 18)
            Text(AppInfo.name)
                .font(.headline)
            Spacer(minLength: 8)
            if let testMode = app.testModeText {
                Text("Test mode")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.15), in: Capsule())
                    .help(testMode)
            }
            if app.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 24, height: 24)
            } else {
                Button { app.requestRefresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                        .background(hovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .help("Refresh")
                .accessibilityLabel("Refresh")
            }
        }
    }
}

/// The bonsai glyph in the app icon's colours: blue pot, brown trunk, green foliage.
struct BonsaiMark: View {
    var body: some View {
        ZStack {
            BonsaiPart(part: .pot).fill(Color(red: 0.29, green: 0.44, blue: 0.59))
            BonsaiPart(part: .trunk).fill(Color(red: 0.53, green: 0.38, blue: 0.25))
            BonsaiPart(part: .foliage).fill(Color(red: 0.31, green: 0.62, blue: 0.27))
        }
        .accessibilityHidden(true)
    }
}

/// One part of `BonsaiGlyph`, scaled from its 64 x 64 grid (y down, like SwiftUI) to the frame.
private struct BonsaiPart: Shape {
    enum Part { case pot, trunk, foliage }
    let part: Part

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch part {
        case .pot: path.addPath(Path(BonsaiGlyph.pot()))
        case .trunk: path.addPath(Path(BonsaiGlyph.trunk()))
        case .foliage: for pad in BonsaiGlyph.foliage() { path.addPath(Path(pad)) }
        }
        let scale = CGAffineTransform(scaleX: rect.width / BonsaiGlyph.grid, y: rect.height / BonsaiGlyph.grid)
        return path.applying(scale).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}
