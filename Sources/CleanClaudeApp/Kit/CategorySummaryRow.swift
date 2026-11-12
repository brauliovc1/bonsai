import SwiftUI

/// One accessible navigation target, with category identity and amount aligned across the Overview.
struct CategorySummaryRow: View {
    let systemImage: String
    let title: String
    let amount: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.medium))
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(amount).font(.body.weight(.medium)).foregroundStyle(Palette.green).monospacedDigit().fixedSize()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }.padding(.vertical, 7).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(amount), \(detail). Review cleanup")
        .help(detail)
    }
}
