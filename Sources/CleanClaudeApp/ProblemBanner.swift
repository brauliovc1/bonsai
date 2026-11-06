import SwiftUI

/// A red strip for problems that stop the screen from showing anything (unreadable settings, no git).
struct ProblemBanner: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.red.opacity(0.08))
    }
}
