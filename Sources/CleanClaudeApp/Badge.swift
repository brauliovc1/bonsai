import CleanAppModel
import CleanCore
import SwiftUI

/// A small capsule label.
struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
            .lineLimit(1)
            .fixedSize()
    }
}

extension Badge {
    init(kind: WorktreeKind) {
        self.init(text: kind.rawValue, color: kind == .claude ? .orange : .secondary)
    }

    init(tone: WorktreeRow.Tone, text: String) {
        let color: Color = switch tone {
        case .autoReady: .green
        case .safe: .blue
        case .inUse: .purple
        case .blocked: .red
        }
        self.init(text: text, color: color)
    }
}
