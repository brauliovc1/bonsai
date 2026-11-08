import CleanAppModel
import CleanCore
import SwiftUI

/// The Docker & Simulators screen: two sections, each with what it costs and its one cleanup command behind
/// a sheet. Prune is disabled with the reason (`DockerReport.pruneBlocker`) when it may not run.
struct DockerSimulatorsView: View {
    @Bindable var model: DockerSimulatorsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                DockerSection(model: model)
                SimulatorsSection(model: model)
                HStack(spacing: 10) {
                    if model.isScanning {
                        ProgressView().controlSize(.small)
                    }
                    if let date = model.lastScanAt {
                        Text("Scanned \(date, format: .relative(presentation: .named))")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Docker & Simulators")
        .toolbar {
            ToolbarItem {
                Button { Task { await model.refresh() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Scan again")
                .disabled(model.isScanning)
            }
        }
        .sheet(isPresented: $model.isShowingDockerSheet, onDismiss: { model.dismissDockerPrune() }) {
            DockerPruneSheet(model: model)
        }
        .sheet(isPresented: $model.isShowingSimulatorsSheet, onDismiss: { model.dismissSimulatorsDelete() }) {
            SimulatorsDeleteSheet(model: model)
        }
        .task { await model.loadIfNeeded() }
    }
}

/// Docker: not installed, not running (with the Docker.raw size), or running with the `docker system df` table.
private struct DockerSection: View {
    let model: DockerSimulatorsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Docker").font(.title3.weight(.semibold))
            Text(model.dockerStatusText)
            if let image = model.dockerDiskImageText {
                Label(image, systemImage: "internaldrive").foregroundStyle(.secondary)
            }
            if let hint = model.startDockerHint {
                Label(hint, systemImage: "power").foregroundStyle(.secondary)
            }
            if model.dockerStatus == .running {
                usageTable
            }
            ForEach(model.dockerWarnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Button("Prune…") { Task { await model.beginDockerPrune() } }
                    .disabled(!model.canPrune)
                    .help(model.pruneDisabledReason ?? "Run \(DockerPruneConfirmation.command) after you confirm")
                if let reason = model.pruneDisabledReason {
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Up to \(DisplayText.bytes(model.dockerReclaimableBytes)) (an estimate; volumes and tagged images stay).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var usageTable: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
            GridRow {
                Text("Type").foregroundStyle(.secondary)
                Text("Count").foregroundStyle(.secondary)
                Text("Size").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                Text("Reclaimable").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            }
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(model.dockerUsage) { line in
                GridRow {
                    Text(line.type)
                    Text(line.countText).foregroundStyle(.secondary)
                    Text(line.sizeText).monospacedDigit()
                    Text(line.reclaimableText).monospacedDigit()
                }
            }
        }
        .font(.callout)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Simulators: device and cache sizes, the unavailable devices, and the installed runtimes (read-only).
private struct SimulatorsSection: View {
    let model: DockerSimulatorsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Simulators").font(.title3.weight(.semibold))
            if model.noXcode {
                Label("Xcode isn't installed (xcode-select -p fails), so simulators aren't looked at.",
                      systemImage: "hammer")
                    .foregroundStyle(.secondary)
            } else if model.simulators == nil {
                Text("Not scanned yet.")
            } else {
                sizes
                unavailable
                runtimes
            }
            ForEach(model.simulatorWarnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
            }
        }
    }

    private var sizes: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
            GridRow {
                Text("Devices")
                Text(DisplayText.bytes(model.devicesBytes)).monospacedDigit()
            }
            GridRow {
                Text("Caches")
                Text(DisplayText.bytes(model.cachesBytes)).monospacedDigit()
            }
        }
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Unavailable devices (their runtime is gone)").font(.headline).padding(.top, 4)
            if model.unavailableDevices.isEmpty {
                Text("None.").foregroundStyle(.secondary)
            } else {
                ForEach(model.unavailableDevices) { device in
                    HStack(alignment: .firstTextBaseline) {
                        Text(device.name)
                        Text(device.runtimeName).foregroundStyle(.secondary)
                        Spacer()
                        Text(DisplayText.bytes(device.sizeBytes)).monospacedDigit()
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Button("Delete unavailable…") { Task { await model.beginSimulatorsDelete() } }
                    .disabled(!model.canDeleteUnavailable)
                    .help("Run \(SimulatorsConfirmation.command) after you confirm")
                Text(model.unavailableDevices.isEmpty ? "Nothing to delete." : "Up to \(DisplayText.bytes(model.unavailableBytes))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var runtimes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Runtimes (read-only)").font(.headline).padding(.top, 4)
            if model.runtimeLines.isEmpty {
                Text("None found.").foregroundStyle(.secondary)
            } else {
                ForEach(model.runtimeLines) { runtime in
                    HStack(alignment: .firstTextBaseline) {
                        Text(runtime.name)
                        Text(runtime.kindText).foregroundStyle(.secondary)
                        Spacer()
                        Text(runtime.sizeText).monospacedDigit()
                    }
                }
            }
            Text(DockerSimulatorsModel.runtimesHint)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
