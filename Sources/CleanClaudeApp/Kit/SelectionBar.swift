import SwiftUI

/// The bar under a list while something is selected: "3 selected · 1.2 GB" on the left, the action on the
/// right.
struct SelectionBar<Actions: View>: View {
    let text: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            actions
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.bar)
    }
}

#Preview("Selection bar") {
    SelectionBar(text: "3 selected · 1.2 GB") {
        Button("Remove…") {}
    }
    .frame(width: 600)
}
