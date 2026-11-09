import SwiftUI

/// One category that has something to free: its icon, name, size (green: it can be freed), what the size is in
/// one line, and one button.
struct CategoryCard: View {
    let systemImage: String
    let title: String
    let sizeText: String
    let detail: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.green)
                    .frame(width: 26, height: 26)
                    .background(Palette.tint(.green), in: RoundedRectangle(cornerRadius: 7))
                Text(title).font(.headline)
                Spacer(minLength: 0)
            }
            Text(sizeText)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.green)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(buttonTitle, action: action)
        }
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.stroke))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), \(sizeText)")
    }
}

#Preview("Category card") {
    CategoryCard(
        systemImage: "arrow.triangle.branch", title: "Worktrees", sizeText: "56.5 GB",
        detail: "83 worktrees you can remove; branches are kept", buttonTitle: "Review and clean"
    ) {}
    .padding()
    .frame(width: 280)
}
