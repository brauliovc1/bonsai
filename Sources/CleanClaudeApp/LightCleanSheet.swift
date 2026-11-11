import CleanAppModel
import CleanCore
import SwiftUI

/// Confirms a light clean. It first looks at the selected worktrees afresh, then lists every folder that
/// will be deleted (relative path and size), the folders left alone with their reasons, and the worktrees
/// that can't be cleaned now. After it runs, the same sheet shows what happened to each folder.
struct LightCleanSheet: View {
    let model: WorktreesModel

    var body: some View {
        Group {
            if let report = model.lightCleanReport {
                LightCleanReportView(report: report) { model.dismissLightClean() }
            } else if let confirmation = model.lightCleanConfirmation {
                confirmPage(confirmation)
            } else {
                SheetProgress(text: "Looking at the selected worktrees…") { model.dismissLightClean() }
            }
        }
        .padding(20)
        .frame(width: 640)
        .frame(minHeight: 300, idealHeight: 520, maxHeight: 720)
        .interactiveDismissDisabled(model.isLightCleaning)
    }

    private func confirmPage(_ confirmation: LightCleanConfirmation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeading(title: confirmation.title)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(confirmation.cleanable) { item in
                        CleanableItemView(item: item)
                    }
                    if !confirmation.others.isEmpty {
                        Text("Nothing is deleted here")
                            .font(.headline)
                            .padding(.top, 4)
                        ForEach(confirmation.others) { item in
                            LeftAloneItemView(item: item)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            if !confirmation.cleanable.isEmpty {
                HStack {
                    Text("Estimated total")
                    Spacer()
                    Text(confirmation.estimatedSizeText)
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
                Text(LightCleanConfirmation.permanentLine)
                    .foregroundStyle(.secondary)
                Text(LightCleanConfirmation.nextTimeLine)
                    .foregroundStyle(.secondary)
            }
            buttons(confirmation)
        }
    }

    private func buttons(_ confirmation: LightCleanConfirmation) -> some View {
        HStack {
            if model.isLightCleaning {
                ProgressView().controlSize(.small)
                Text("Cleaning \(min(model.lightCleansDone + 1, confirmation.cleanable.count)) of \(confirmation.cleanable.count)…")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel", role: .cancel) { model.dismissLightClean() }
                .keyboardShortcut(.cancelAction)
                .disabled(model.isLightCleaning)
            if !confirmation.cleanable.isEmpty {
                // Deliberately not the default button: Return never deletes anything.
                Button(confirmation.deleteButtonTitle, role: .destructive) {
                    model.queueLightClean(confirmation)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.red)
                .disabled(model.isLightCleaning)
            }
        }
    }
}

/// One worktree with folders to delete: each folder, then the ones left alone.
private struct CleanableItemView: View {
    let item: LightCleanConfirmation.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SheetItemHeader(title: item.repoName, detail: item.branchText, path: item.worktree.path, sizeText: item.estimatedSizeText)
            ForEach(item.candidates, id: \.relativePath) { candidate in
                HStack(alignment: .firstTextBaseline) {
                    Label(candidate.relativePath, systemImage: "folder")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    SizeText(bytes: candidate.estimatedBytes)
                }
                if !candidate.packageClones.isEmpty {
                    Label(
                        "Goes with \(candidate.packageClones.count) package "
                            + "\(candidate.packageClones.count == 1 ? "clone" : "clones") that can be fetched again.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            SkippedList(skipped: item.skipped, unreadable: item.unreadable)
        }
    }
}

/// A worktree where nothing is deleted, with why.
private struct LeftAloneItemView: View {
    let item: LightCleanConfirmation.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SheetItemHeader(title: item.repoName, detail: item.branchText, path: item.worktree.path)
            if let reason = item.leftAloneReason {
                Label(reason, systemImage: "nosign")
            }
            SkippedList(skipped: item.skipped, unreadable: item.unreadable)
        }
        .foregroundStyle(.secondary)
        .opacity(0.85)
    }
}

/// Folders found by name and left alone, one line each with the reason, and folders that couldn't be read.
private struct SkippedList: View {
    let skipped: [LightCleanSkip]
    let unreadable: [String]

    var body: some View {
        ForEach(skipped, id: \.relativePath) { skip in
            Label {
                Text("\(skip.relativePath) is left alone: \(CleanupPresentation.reason(skip.reason))")
            } icon: {
                Image(systemName: "nosign")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        ForEach(unreadable, id: \.self) { folder in
            Label("\(folder) couldn't be read; nothing below it was looked at.", systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(Palette.orange)
        }
    }
}
