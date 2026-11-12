import SwiftUI

/// A list's purpose stays in the content; the native titlebar supplies its screen title.
struct CleanupPageHeader: View {
    let subtitle: String

    var body: some View {
        Text(subtitle)
            .font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.vertical, 12)
    }
}
