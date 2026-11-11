import CleanAppModel
import CleanCore
import SwiftUI

/// Confirms cleaning the selected projects. It first looks at them afresh, then lists the projects, how many
/// folders and how much, each project's folders with sizes, the reinstall note for a recent one, and how to
/// get the folders back. Projects "Select all idle" picked that were worked on since are listed apart, unticked.
/// After it runs, the light-clean report shows what happened to each folder.
struct ProjectsCleanSheet: View {
    let model: ProjectsModel

    var body: some View {
        Group {
            if let report = model.cleanReport {
                LightCleanReportView(report: report) { model.dismissClean() }
            } else if let confirmation = model.confirmation {
                confirmPage(confirmation)
            } else {
                SheetProgress(text: "Looking at the selected projects…") { model.dismissClean() }
            }
        }
        .padding(20)
        .frame(width: 640)
        .frame(minHeight: 300, idealHeight: 540, maxHeight: 720)
        .interactiveDismissDisabled(model.isCleaning)
    }

    private func confirmPage(_ confirmation: ProjectsConfirmation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeading(title: confirmation.title, subtitle: confirmation.summary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(confirmation.ready) { item in
                        ProjectCleanItemView(item: item)
                    }
                    if !confirmation.changed.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Changed since you selected it").font(.headline)
                            Text("Select all idle picked these, but they are no longer idle \(model.threshold) days. "
                                + "Nothing is deleted here unless you tick it.")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                        ForEach(confirmation.changed) { item in
                            VStack(alignment: .leading, spacing: 5) {
                                Toggle("Delete these folders too", isOn: Binding(
                                    get: { confirmation.included.contains(item.id) },
                                    set: { model.setIncluded(item.id, $0) }
                                ))
                                .disabled(model.isCleaning)
                                ProjectCleanItemView(item: item)
                            }
                            .opacity(confirmation.included.contains(item.id) ? 1 : 0.7)
                        }
                    }
                    if !confirmation.others.isEmpty {
                        Text("Nothing is deleted here").font(.headline).padding(.top, 4)
                        ForEach(confirmation.others) { item in
                            ProjectLeftAloneView(item: item)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            if !confirmation.cleanable.isEmpty {
                Text(LightCleanConfirmation.permanentLine).foregroundStyle(.secondary)
            }
            buttons(confirmation)
        }
    }

    private func buttons(_ confirmation: ProjectsConfirmation) -> some View {
        HStack {
            if model.isCleaning {
                ProgressView().controlSize(.small)
                Text("Cleaning \(min(model.cleansDone + 1, confirmation.cleanable.count)) of \(confirmation.cleanable.count)…")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel", role: .cancel) { model.dismissClean() }
                .keyboardShortcut(.cancelAction)
                .disabled(model.isCleaning)
            if !confirmation.cleanable.isEmpty {
                // Deliberately not the default button: Return never deletes anything.
                Button(confirmation.deleteButtonTitle, role: .destructive) {
                    model.queueClean(confirmation)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.red)
                .disabled(model.isCleaning)
            }
        }
    }
}

/// One project with folders to delete: the note, each folder, how to get them back, the folders left alone.
private struct ProjectCleanItemView: View {
    let item: ProjectsConfirmation.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SheetItemHeader(title: item.name, detail: item.repoName == item.name ? nil : item.repoName, path: item.worktree.path, bytes: item.estimatedBytes)
            if let note = item.idleNote {
                Label(note, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Palette.orange)
            }
            ForEach(item.candidates, id: \.relativePath) { candidate in
                HStack(alignment: .firstTextBaseline) {
                    Label(candidate.relativePath, systemImage: "folder")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    SizeText(bytes: candidate.estimatedBytes)
                }
            }
            if !item.rebuildLines.isEmpty {
                Label("To get them back: " + item.rebuildLines.joined(separator: "; "), systemImage: "arrow.uturn.backward")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(item.lightClean.skipped, id: \.relativePath) { skip in
                Label("\(skip.relativePath) is left alone: \(CleanupPresentation.reason(skip.reason))", systemImage: "nosign")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A project where nothing is deleted now, with why.
private struct ProjectLeftAloneView: View {
    let item: ProjectsConfirmation.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SheetItemHeader(title: item.name, path: item.worktree.path)
            if let reason = item.lightClean.leftAloneReason {
                Label(reason, systemImage: "nosign")
            }
        }
        .foregroundStyle(.secondary)
        .opacity(0.85)
    }
}
