import SwiftUI

struct QuickCleanStatusView: View {
    let isPreparing: Bool
    let problem: String?
    let retry: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeading(title: "Quick clean", subtitle: "Review eligible items before anything is cleaned.")
            if isPreparing {
                ProgressView("Checking worktrees, dependencies, caches and old downloads…")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Worktrees and project dependencies must be idle for at least 7 days. Each category keeps its usual safety checks.")
                    .font(.callout).foregroundStyle(.secondary)
            } else if let problem {
                ProblemBanner(text: problem)
            }
            Spacer(minLength: 24)
            HStack {
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Spacer()
                if !isPreparing { Button("Try again", action: retry) }
            }
        }.padding(24)
    }
}
