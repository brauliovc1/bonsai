import CleanAppModel
import SwiftUI

/// The Settings window: General and Auto mode.
struct SettingsView: View {
    @Bindable var model: SettingsModel
    let autoMode: AutoModeModel
    let launchAtLogin: LaunchAtLoginModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            GeneralSettingsView(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsModel.Tab.general)
            AutoModeSettingsView(model: autoMode, launchAtLogin: launchAtLogin)
                .tabItem { Label("Auto clean", systemImage: "clock.badge.checkmark") }
                .tag(SettingsModel.Tab.autoMode)
        }
        .frame(width: 540)
        .frame(minHeight: 360)
        .onAppear { model.load() }
    }
}

/// General: scan roots, the idle threshold, and the low-space warning. Every change is saved at once.
struct GeneralSettingsView: View {
    let model: SettingsModel
    @State private var selection: String?

    var body: some View {
        Form {
            Section {
                PageHeader(title: "General", subtitle: "Choose where Bonsai looks and when a project counts as idle.")
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("Project folders to scan") {
                rootsList
                HStack {
                    Button("Add…") { add() }
                    Button("Remove") { remove() }
                        .disabled(selection == nil)
                    Spacer()
                }
                if let note = model.overrideText {
                    Text(note).font(.callout).foregroundStyle(Palette.orange)
                }
                Text(model.scanningText).font(.callout).foregroundStyle(.secondary)
            }
            Section("Idle threshold") {
                Stepper(value: idleBinding, in: SettingsModel.idleThresholdRange) {
                    Text("\(model.idleThresholdDays) days")
                        .monospacedDigit()
                }
                Text("Projects and worktrees count as idle after this many days without activity. Auto clean uses the same threshold.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Low disk space") {
                Stepper(value: lowSpaceBinding, in: SettingsModel.lowSpaceRange) {
                    Text("Warn below \(model.lowSpaceWarningGB) GB free")
                        .monospacedDigit()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var rootsList: some View {
        List(selection: $selection) {
            if model.scanRoots.isEmpty {
                Text(SettingsModel.emptyRootsText).foregroundStyle(.secondary)
            }
            ForEach(model.scanRoots, id: \.self) { root in
                rootRow(root)
            }
        }
        .frame(minHeight: 90, maxHeight: 140)
    }

    @ViewBuilder
    private func rootRow(_ root: String) -> some View {
        let refusal = model.skippedReason(of: root)
        VStack(alignment: .leading, spacing: 2) {
            Text(root)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(root)
                .strikethrough(refusal != nil)
            if let refusal {
                Text("Skipped: \(refusal)")
                    .font(.caption)
                    .foregroundStyle(Palette.orange)
            }
        }
        .tag(root)
    }

    private var idleBinding: Binding<Int> {
        Binding(get: { model.idleThresholdDays }, set: { days in Task { await model.setIdleThreshold(days) } })
    }

    private var lowSpaceBinding: Binding<Int> {
        Binding(get: { model.lowSpaceWarningGB }, set: { model.setLowSpaceWarning($0) })
    }

    private func add() {
        let folders = FolderPicker.chooseFolders()
        guard !folders.isEmpty else { return }
        Task {
            for folder in folders { await model.addRoot(folder) }
        }
    }

    private func remove() {
        guard let root = selection else { return }
        selection = nil
        Task { await model.removeRoot(root) }
    }
}
