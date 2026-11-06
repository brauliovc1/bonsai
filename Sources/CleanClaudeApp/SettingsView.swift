import CleanAppModel
import SwiftUI

/// The Settings window. A TabView so later phases add their own tab (Auto mode).
struct SettingsView: View {
    let model: SettingsModel

    var body: some View {
        TabView {
            GeneralSettingsView(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
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
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("Scan roots") {
                rootsList
                HStack {
                    Button("Add…") { add() }
                    Button("Remove") { remove() }
                        .disabled(selection == nil)
                    Spacer()
                }
                if let note = model.overrideText {
                    Text(note).font(.callout).foregroundStyle(.orange)
                }
                Text(model.scanningText).font(.callout).foregroundStyle(.secondary)
            }
            Section("Idle threshold") {
                Stepper(value: idleBinding, in: SettingsModel.idleThresholdRange) {
                    Text("\(model.idleThresholdDays) days")
                        .monospacedDigit()
                }
                Text("A worktree counts as idle after this many days without activity. It sets the statuses "
                    + "(auto-ready needs this many idle days) and is used by auto mode.")
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
                Text(root)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(root)
                    .tag(root)
            }
        }
        .frame(minHeight: 90, maxHeight: 140)
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
