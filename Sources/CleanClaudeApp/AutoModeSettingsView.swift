import CleanAppModel
import SwiftUI

/// Settings › Auto mode: on/off, the report-only window, the rules it follows, Run now with the last run,
/// and launch at login (auto mode only runs while the app does).
struct AutoModeSettingsView: View {
    let model: AutoModeModel
    let launchAtLogin: LaunchAtLoginModel

    var body: some View {
        Form {
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle("Remove idle worktrees automatically", isOn: enabledBinding)
                Text("Once a day \(AppInfo.name) removes worktrees idle \(model.idleThresholdDays)+ days that pass "
                    + "every safety check. Branches are kept, and worktrees with local work only get a notification. "
                    + "Nothing runs while \(AppInfo.name) is closed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let note = model.reportOnlyText {
                    Label(note, systemImage: "eye")
                        .foregroundStyle(.orange)
                }
            }
            Section("Rules") {
                LabeledContent("Idle threshold") {
                    Text("\(model.idleThresholdDays) days").monospacedDigit()
                }
                Text(AutoModeModel.idleThresholdNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Include Claude worktrees", isOn: claudeBinding)
                Text(AutoModeModel.claudeWarning)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Runs") {
                HStack(spacing: 10) {
                    Button(model.isReportOnly ? "Run now (report only)" : "Run now") {
                        Task { await model.runNow() }
                    }
                    .disabled(!model.canRunNow)
                    if model.isRunning {
                        ProgressView().controlSize(.small)
                        Text("Running…").foregroundStyle(.secondary)
                    } else if model.app.isCleaningUp {
                        Text("Another cleanup is running.").foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text(model.lastRunText)
                ForEach(model.lastRunDetails, id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(model.nextRunText)
                    .foregroundStyle(.secondary)
            }
            Section("Launch at login") {
                Toggle("Open \(AppInfo.name) at login", isOn: launchBinding)
                Text(launchAtLogin.statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if launchAtLogin.needsApproval {
                    Button("Open Login Items Settings…") { launchAtLogin.openSystemSettings() }
                }
                if let error = launchAtLogin.error {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.app.reloadSettings()
            launchAtLogin.refresh()
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { model.isEnabled }, set: { on in
            if on { Task { await model.enable() } } else { model.disable() }
        })
    }

    private var claudeBinding: Binding<Bool> {
        Binding(get: { model.includesClaudeWorktrees }, set: { on in
            Task { await model.setIncludesClaudeWorktrees(on) }
        })
    }

    private var launchBinding: Binding<Bool> {
        Binding(get: { launchAtLogin.isOn }, set: { launchAtLogin.setEnabled($0) })
    }
}
