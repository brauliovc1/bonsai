import CleanAppModel
import CleanCore
import SwiftUI

/// The strip under a table: scan state, scan issues, and how many rows are shown.
struct ScanStatusBar: View {
    let app: AppModel
    let shown: Int
    let total: Int
    @State private var showingIssues = false

    var body: some View {
        HStack(spacing: 10) {
            if app.isScanning {
                ProgressView().controlSize(.small)
            }
            ScanTimeText(app: app)
            if !app.issues.isEmpty {
                Button("\(app.issues.count) \(app.issues.count == 1 ? "issue" : "issues")") { showingIssues = true }
                    .buttonStyle(.link)
                    .popover(isPresented: $showingIssues) { issueList }
            }
            Spacer()
            Text(shown == total ? DisplayText.worktrees(total) : "\(shown) of \(DisplayText.worktrees(total))")
            Text("\(DisplayText.bytes(app.disk.freeBytes)) free")
                .monospacedDigit()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var issueList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(app.issues, id: \.self) { issue in
                    Text(issue.description).textSelection(.enabled)
                }
            }
            .padding(12)
        }
        .frame(width: 420)
        .frame(maxHeight: 300)
    }
}
