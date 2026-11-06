import SwiftUI

/// A sheet's first page while the model looks at things afresh: a spinner, what it is doing, and Cancel.
struct SheetProgress: View {
    let text: String
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text(text).foregroundStyle(.secondary)
            Spacer()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
