import CleanAppModel
import SwiftUI

/// A slim strip with what the settings folder's move said at launch (both folders there, or not moved yet),
/// until it is dismissed: said once, on the Overview.
struct LaunchNoticeBanner: View {
    let app: AppModel

    var body: some View {
        if let notice = app.launchNotice {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "info.circle.fill").foregroundStyle(.blue)
                Text(notice)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Button("OK") { app.launchNotice = nil }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.blue.opacity(0.10), ignoresSafeAreaEdges: [])
        }
    }
}
