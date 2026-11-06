import CleanAppModel
import SwiftUI

/// The second page of the Docker and Simulators sheets: what the one command did, or why it didn't run,
/// the command's output, and a log failure as an error.
struct CommandReportView: View {
    let report: CleanupCommandReport
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(report.summary).font(.title3.weight(.semibold))
            } icon: {
                Image(systemName: icon).foregroundStyle(color)
            }
            Text(report.command)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            if let logError = report.logError {
                Label("The command ran, but the log entry was not written: \(logError)", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }
            if !report.output.isEmpty {
                ScrollView {
                    Text(report.output)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
                .padding(8)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var icon: String {
        if report.logError != nil || (report.didRun && !report.succeeded) || !report.didRun {
            return "xmark.octagon.fill"
        }
        return "checkmark.circle.fill"
    }

    private var color: Color {
        report.didRun && report.succeeded && report.logError == nil ? .green : .red
    }
}
