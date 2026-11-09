import SwiftUI

/// What a screen shows when it has nothing to list: a headline, one line, and an optional action.
struct EmptyState: View {
    let systemImage: String
    let headline: String
    let line: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            Text(headline)
                .font(.title3.weight(.semibold))
            Text(line)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: 380)
        .padding(24)
    }
}

#Preview("Empty state") {
    EmptyState(
        systemImage: "checkmark.circle", headline: "Nothing to remove",
        line: "No worktree can be removed right now.", actionTitle: "Show all"
    ) {}
}
