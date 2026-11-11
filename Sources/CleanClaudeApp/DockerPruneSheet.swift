import CleanAppModel
import SwiftUI

/// Confirms `docker system prune -f`. It first asks Docker again, then shows the exact command, what it
/// removes and what it keeps. Prune is disabled with the reason when it may not run.
struct DockerPruneSheet: View {
    let model: DockerSimulatorsModel

    var body: some View {
        Group {
            if let report = model.dockerReport {
                CommandReportView(report: report) { model.dismissDockerPrune() }
            } else if let confirmation = model.dockerConfirmation {
                confirmPage(confirmation)
            } else {
                SheetProgress(text: "Asking Docker…") { model.dismissDockerPrune() }
            }
        }
        .padding(20)
        .frame(width: 560)
        .frame(minHeight: 300, idealHeight: 460, maxHeight: 680)
        .interactiveDismissDisabled(model.isPruning)
    }

    private func confirmPage(_ confirmation: DockerPruneConfirmation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeading(title: confirmation.title)
            Text("This runs")
            Text(DockerPruneConfirmation.command)
                .font(.system(.title3, design: .monospaced))
                .textSelection(.enabled)
            if let line = confirmation.commandLine {
                Text(line)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    list("It removes", items: DockerPruneConfirmation.removes, icon: "minus.circle", color: Palette.grey)
                    list("It keeps", items: DockerPruneConfirmation.keeps, icon: "checkmark.circle", color: Palette.blue)
                    if confirmation.isAllowed && confirmation.hasSizeEstimate {
                        Text("Docker says up to \(DisplayText.bytes(confirmation.estimatedBytes)) could be freed. "
                            + "That is an upper bound: unused tagged images stay.")
                            .foregroundStyle(.secondary)
                    }
                    if confirmation.isAllowed && !confirmation.hasSizeEstimate {
                        Text("Docker’s space estimate is unavailable.").foregroundStyle(.secondary)
                    }
                    Text(DockerPruneConfirmation.slowLine).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            if let blocker = confirmation.blocker {
                Label(blocker, systemImage: "nosign").foregroundStyle(Palette.orange)
            }
            HStack {
                if model.isPruning {
                    ProgressView().controlSize(.small)
                    Text("Pruning…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { model.dismissDockerPrune() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isPruning)
                // Deliberately not the default button: Return never prunes.
                Button(confirmation.buttonTitle, role: .destructive) { model.queueDockerPrune(confirmation) }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.red)
                    .disabled(!confirmation.isAllowed || model.isPruning)
                    .help(confirmation.blocker ?? "Run \(DockerPruneConfirmation.command)")
            }
        }
    }

    private func list(_ title: String, items: [String], icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            ForEach(items, id: \.self) { item in
                Label { Text(item) } icon: { Image(systemName: icon).foregroundStyle(color) }
            }
        }
    }
}
