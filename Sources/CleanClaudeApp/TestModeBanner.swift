import SwiftUI

/// A slim strip saying the app scans only the folders in CLEAN_CLAUDE_SCAN_ROOTS (a demo world), so its
/// repos aren't taken for the Mac's own.
struct TestModeBanner: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: "testtube.2").foregroundStyle(.orange)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.orange.opacity(0.12))
        .help(text)
    }
}
