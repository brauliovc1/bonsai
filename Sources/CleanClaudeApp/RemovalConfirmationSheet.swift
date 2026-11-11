import CleanAppModel
import CleanCore
import SwiftUI

/// Confirms a removal. It first looks at the selected worktrees afresh, then shows the allowed items with
/// their notes and warnings, the blocked ones greyed out with their reasons, and the estimated total. After
/// it runs, the same sheet shows what happened to each item.
struct RemovalConfirmationSheet: View {
    let model: WorktreesModel

    var body: some View {
        Group {
            if let report = model.report {
                RemovalReportView(report: report) { model.dismissRemoval() }
            } else if let confirmation = model.confirmation {
                confirmPage(confirmation)
            } else {
                SheetProgress(text: "Checking the selected worktrees…") { model.dismissRemoval() }
            }
        }
        .padding(20)
        .frame(width: 600)
        .frame(minHeight: 280, idealHeight: 460, maxHeight: 700)
        .interactiveDismissDisabled(model.isRemoving)
    }

    private func confirmPage(_ confirmation: RemovalConfirmation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Remove… is offered only for worktrees that can go, so "nothing" here means they changed since the
            // last scan; each one below says why.
            SheetHeading(title: confirmation.title)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(confirmation.allowed) { item in
                        AllowedItemView(item: item)
                    }
                    if !confirmation.blocked.isEmpty {
                        Text("Can't be removed, so they are left alone")
                            .font(.headline)
                            .padding(.top, 4)
                        ForEach(confirmation.blocked) { item in
                            BlockedItemView(item: item)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            if !confirmation.allowed.isEmpty {
                HStack {
                    Text("Estimated total")
                    Spacer()
                    Text(confirmation.estimatedSizeText)
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
                Text(RemovalConfirmation.keptLine)
                    .foregroundStyle(.secondary)
            }
            buttons(confirmation)
        }
    }

    private func buttons(_ confirmation: RemovalConfirmation) -> some View {
        HStack {
            if model.isRemoving {
                ProgressView().controlSize(.small)
                Text("Removing \(min(model.removalsDone + 1, confirmation.allowed.count)) of \(confirmation.allowed.count)…")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel", role: .cancel) { model.dismissRemoval() }
                .keyboardShortcut(.cancelAction)
                .disabled(model.isRemoving)
            if !confirmation.allowed.isEmpty {
                // Deliberately not the default button: Return never removes anything.
                Button(confirmation.removeButtonTitle, role: .destructive) {
                    model.queueRemoval(confirmation)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.red)
                .disabled(model.isRemoving)
            }
        }
    }
}

/// One item that will be removed, with everything to know first.
private struct AllowedItemView: View {
    let item: RemovalConfirmation.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SheetItemHeader(title: item.repoName, detail: item.branchText, path: item.worktree.path, bytes: item.estimatedBytes)
            if let warning = item.claudeWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.orange)
            }
            ForEach(item.notes, id: \.self) { note in
                Label(WorktreeStatusText.sentence(for: note), systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
            if !item.ignoredUserFiles.isEmpty {
                Label {
                    Text("Ignored files that are not build output are deleted with it: "
                        + item.ignoredUserFiles.joined(separator: ", "))
                } icon: {
                    Image(systemName: "doc.badge.ellipsis")
                }
                .foregroundStyle(Palette.orange)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// One item that stays, greyed out, with why.
private struct BlockedItemView: View {
    let item: RemovalConfirmation.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SheetItemHeader(title: item.repoName, detail: item.branchText, path: item.worktree.path, bytes: item.estimatedBytes)
            ForEach(item.blockers, id: \.self) { reason in
                Label(WorktreeStatusText.sentence(for: reason), systemImage: "nosign")
            }
        }
        .foregroundStyle(.secondary)
        .opacity(0.75)
        .fixedSize(horizontal: false, vertical: true)
    }
}
