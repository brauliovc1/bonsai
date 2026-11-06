import CleanAppModel
import SwiftUI

/// Confirms `xcrun simctl delete unavailable`. It first looks at the simulators again, then shows the exact
/// command and the unavailable devices it deletes.
struct SimulatorsDeleteSheet: View {
    let model: DockerSimulatorsModel

    var body: some View {
        Group {
            if let report = model.simulatorsReport {
                CommandReportView(report: report) { model.dismissSimulatorsDelete() }
            } else if let confirmation = model.simulatorsConfirmation {
                confirmPage(confirmation)
            } else {
                SheetProgress(text: "Looking at the simulators…") { model.dismissSimulatorsDelete() }
            }
        }
        .padding(20)
        .frame(width: 560)
        .frame(minHeight: 280, idealHeight: 420, maxHeight: 680)
        .interactiveDismissDisabled(model.isDeletingDevices)
    }

    private func confirmPage(_ confirmation: SimulatorsConfirmation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(confirmation.devices.isEmpty ? "Nothing to delete" : "Delete the unavailable simulators?")
                .font(.title2.weight(.semibold))
            Text("This runs")
            Text(SimulatorsConfirmation.command)
                .font(.system(.title3, design: .monospaced))
                .textSelection(.enabled)
            if let line = confirmation.commandLine {
                Text(line)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(confirmation.devices) { device in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(device.name).fontWeight(.semibold)
                                Text(device.runtimeName).foregroundStyle(.secondary)
                                Spacer()
                                Text(DisplayText.bytes(device.sizeBytes)).monospacedDigit()
                            }
                            Text(device.udid).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    if !confirmation.devices.isEmpty {
                        Text("About \(DisplayText.bytes(confirmation.estimatedBytes)) in total.")
                            .foregroundStyle(.secondary)
                    }
                    Text(SimulatorsConfirmation.keepsLine).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            if confirmation.report.state != .available, let blocker = confirmation.blocker {
                Label(blocker, systemImage: "nosign").foregroundStyle(.red)
            }
            HStack {
                if model.isDeletingDevices {
                    ProgressView().controlSize(.small)
                    Text("Deleting…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { model.dismissSimulatorsDelete() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isDeletingDevices)
                if confirmation.isAllowed {
                    // Deliberately not the default button: Return never deletes anything.
                    Button("Delete unavailable", role: .destructive) {
                        Task { await model.confirmSimulatorsDelete(confirmation) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(model.isDeletingDevices || model.app.isCleaningUp)
                }
            }
        }
    }
}
