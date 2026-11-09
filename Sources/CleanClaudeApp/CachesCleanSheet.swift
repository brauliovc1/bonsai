import CleanAppModel
import SwiftUI

/// Confirms cleaning tool caches. It first scans again, then lists the entries that will be cleaned (size,
/// folder, when it comes back, what stays) and the selected ones that are left alone with why. After it runs, the
/// same sheet shows what happened to each.
struct CachesCleanSheet: View {
    let model: CachesModel

    var body: some View {
        Group {
            if let report = model.cleanReport {
                resultPage(report)
            } else if let confirmation = model.confirmation {
                confirmPage(confirmation)
            } else {
                SheetProgress(text: "Looking at the caches again…") { model.dismissClean() }
            }
        }
        .padding(20)
        .frame(width: 640)
        .frame(minHeight: 300, idealHeight: 480, maxHeight: 720)
        .interactiveDismissDisabled(model.isCleaning)
    }

    private func confirmPage(_ confirmation: CachesConfirmation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(confirmation.allowed.isEmpty ? "Nothing can be cleaned" : "\(confirmation.cleanButtonTitle)?")
                .font(.title2.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(confirmation.allowed) { item in
                        CacheItemView(item: item)
                    }
                    if !confirmation.blocked.isEmpty {
                        Text("Left alone").font(.headline).padding(.top, 4)
                        ForEach(confirmation.blocked) { item in
                            CacheItemView(item: item).foregroundStyle(.secondary).opacity(0.85)
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
                    Text(DisplayText.bytes(confirmation.estimatedTotalBytes)
                        + (confirmation.hasUnknownSizes ? " (some sizes unknown)" : ""))
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
                Text(CachesConfirmation.downloadsLine).foregroundStyle(.secondary)
            }
            buttons(confirmation)
        }
    }

    private func buttons(_ confirmation: CachesConfirmation) -> some View {
        HStack {
            if model.isCleaning {
                ProgressView().controlSize(.small)
                Text("Cleaning…").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel", role: .cancel) { model.dismissClean() }
                .keyboardShortcut(.cancelAction)
                .disabled(model.isCleaning)
            if !confirmation.allowed.isEmpty {
                // Deliberately not the default button: Return never deletes anything.
                Button(confirmation.cleanButtonTitle, role: .destructive) {
                    Task { await model.confirmClean(confirmation) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(model.isCleaning || model.app.isCleaningUp)
            }
        }
    }

    private func resultPage(_ report: CachesCleanReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(report.summary).font(.title2.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(report.outcomes) { outcome in
                        CacheOutcomeView(outcome: outcome)
                    }
                    ForEach(report.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
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
                Button("Done") { model.dismissClean() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// One entry: name and size, why it is left alone (if it is), its folder, when it comes back, and what stays.
private struct CacheItemView: View {
    let item: CachesConfirmation.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name).fontWeight(.semibold)
                Spacer()
                Text(item.sizeText).monospacedDigit()
            }
            if let reason = item.leftAloneReason {
                Label(reason, systemImage: "nosign")
            }
            Text(item.folderText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            if item.isAllowed {
                Label(item.note, systemImage: "arrow.down.circle").foregroundStyle(.secondary)
                if !item.keeps.isEmpty {
                    Label("Keeps " + item.keeps.joined(separator: ", "), systemImage: "lock")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CacheOutcomeView: View {
    let outcome: CachesCleanOutcome

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(outcome.item.name).fontWeight(.semibold)
                Text(detail).font(.callout).foregroundStyle(color == .green ? .secondary : color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var detail: String {
        switch outcome.status {
        case .cleaned(let removed, let freed, let failures):
            "Cleaned \(removed) \(removed == 1 ? "item" : "items"). Freed \(DisplayText.bytes(freed)) "
                + "(estimate \(DisplayText.bytes(outcome.item.bytes)))."
                + (failures.isEmpty ? "" : " \(failures.count) couldn't be removed: " + failures.prefix(3).joined(separator: "; "))
        case .refused(let why): "Refused, left alone: \(why)"
        case .failed(let failures): "Failed: " + failures.prefix(3).joined(separator: "; ")
        }
    }

    private var icon: String {
        switch outcome.status {
        case .cleaned(_, _, let failures): failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        case .refused: "arrow.triangle.2.circlepath.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch outcome.status {
        case .cleaned(_, _, let failures): failures.isEmpty ? .green : .orange
        case .refused: .orange
        case .failed: .red
        }
    }
}
