import CleanAppModel
import SwiftUI

/// Inline details avoid native inspector ideal-size feedback while keeping selection and actions unchanged.
struct WorktreeDetailsPanel: View {
    let model: WorktreesModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Details").font(.headline)
                Spacer(minLength: 8)
                Button { model.isShowingDetails = false } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close details")
                .help("Hide details (Space)")
            }.padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            WorktreeDetailsView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
