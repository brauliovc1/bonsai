import CleanAppModel
import SwiftUI

/// Confirms deleting orphaned DerivedData. It first scans again, then lists the folders that will be
/// deleted (name, project that is gone, size) and the selected ones that are left alone with why. After it
/// runs, the same sheet shows what happened to each folder.
struct DerivedDataDeleteSheet: View {
    let model: DerivedDataModel

    var body: some View {
        Group {
            if let report = model.cleanupReport {
                resultPage(report)
            } else if let confirmation = model.confirmation {
                confirmPage(confirmation)
            } else {
                SheetProgress(text: "Scanning DerivedData again…") { model.dismissDelete() }
            }
        }
        .padding(20)
        .frame(width: 620)
        .frame(minHeight: 280, idealHeight: 440, maxHeight: 700)
        .interactiveDismissDisabled(model.isDeleting)
    }

    private func confirmPage(_ confirmation: DerivedDataConfirmation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeading(title: confirmation.title)
            if let refusal = confirmation.refusal {
                ProblemBanner(text: "The DerivedData folder is refused: \(refusal)")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(confirmation.allowed) { item in
                        FolderItemView(item: item)
                    }
                    if !confirmation.blocked.isEmpty {
                        Text("Left alone").font(.headline).padding(.top, 4)
                        ForEach(confirmation.blocked) { item in
                            FolderItemView(item: item).foregroundStyle(.secondary).opacity(0.85)
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
                Text(DerivedDataConfirmation.permanentLine)
                    .foregroundStyle(.secondary)
            }
            buttons(confirmation)
        }
    }

    private func buttons(_ confirmation: DerivedDataConfirmation) -> some View {
        HStack {
            if model.isDeleting {
                ProgressView().controlSize(.small)
                Text("Deleting…").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel", role: .cancel) { model.dismissDelete() }
                .keyboardShortcut(.cancelAction)
                .disabled(model.isDeleting)
            if !confirmation.allowed.isEmpty {
                // Deliberately not the default button: Return never deletes anything.
                Button(confirmation.deleteButtonTitle, role: .destructive) {
                    model.queueDelete(confirmation)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.red)
                .disabled(model.isDeleting)
            }
        }
    }

    private func resultPage(_ report: DerivedDataCleanupReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeading(title: report.headline, subtitle: report.summary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if report.outcomes.contains(where: \.isDeleted) { Text("Done").font(.headline) }
                    ForEach(report.outcomes.filter(\.isDeleted)) { outcome in
                        OutcomeView(outcome: outcome)
                    }
                    if report.outcomes.contains(where: { !$0.isDeleted }) { Text("Skipped").font(.headline).padding(.top, 4) }
                    ForEach(report.outcomes.filter { !$0.isDeleted }) { outcome in
                        OutcomeView(outcome: outcome)
                    }
                    ForEach(report.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(Palette.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            Text("Freed space is measured from the disk, so it can be lower than the estimate.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Done") { model.dismissDelete() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// One folder: its name and size, the project that is gone (or why it stays), and its path.
private struct FolderItemView: View {
    let item: DerivedDataConfirmation.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                Spacer()
                SizeText(bytes: item.bytes)
            }
            if let reason = item.leftAloneReason {
                Label(reason, systemImage: "nosign")
            } else if let project = item.workspacePath {
                Label("Its project is gone: \(project)", systemImage: "questionmark.folder")
                    .foregroundStyle(.secondary)
            }
            Text(item.folder)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct OutcomeView: View {
    let outcome: DerivedDataOutcome

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(outcome.item.name).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                Text(detail).font(.callout).foregroundStyle(detailColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var detail: String {
        switch outcome.status {
        case .deleted(let freed):
            "Deleted. Freed \(DisplayText.bytes(freed)) (estimate \(DisplayText.bytes(outcome.item.bytes)))."
        case .refused(let why): "Left alone: \(why)"
        case .failed(let message): "Couldn't clean: \(message)"
        }
    }

    private var icon: String {
        switch outcome.status {
        case .deleted: "checkmark.circle.fill"
        case .refused: "arrow.triangle.2.circlepath.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch outcome.status {
        case .deleted: Palette.green
        case .refused: Palette.orange
        case .failed: Palette.orange
        }
    }

    private var detailColor: Color {
        switch outcome.status {
        case .deleted: .secondary
        case .refused: Palette.orange
        case .failed: Palette.orange
        }
    }
}
