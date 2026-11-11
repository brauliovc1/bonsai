import CleanAppModel
import SwiftUI

struct DockerSimulatorsView: View {
    @Bindable var model: DockerSimulatorsModel
    @State private var sort: ContentSort = .size
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Docker & Simulators", subtitle: "Clean unused Docker data and devices that can no longer boot.") {
                    Button("Refresh") { Task { await model.refresh() } }.disabled(model.isScanning)
                }
                ContentSortBar(selection: $sort)
                HStack(alignment: .top, spacing: 18) {
                    docker.frame(maxWidth: .infinity)
                    simulators.frame(maxWidth: .infinity)
                }
                if model.isScanning { ProgressView("Measuring…") }
            }.padding(20)
        }
        .navigationTitle("Docker & Simulators")
        .sheet(isPresented: $model.isShowingDockerSheet, onDismiss: { model.dismissDockerPrune() }) { DockerPruneSheet(model: model) }
        .sheet(isPresented: $model.isShowingSimulatorsSheet, onDismiss: { model.dismissSimulatorsDelete() }) { SimulatorsDeleteSheet(model: model) }
        .task { await model.loadIfNeeded() }
    }
    private var docker: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.dockerStatus == .notRunning || model.dockerStatus == .notInstalled {
                GroupedSection(title: "Docker") {
                    EmptyState(systemImage: "shippingbox", headline: model.dockerStatus == .notRunning ? "Start Docker to clean" : "Docker isn't installed",
                               line: model.dockerDiskImageText ?? "Install Docker Desktop to manage its unused data here.")
                }
            } else {
                CategoryCard(systemImage: "shippingbox", title: "Docker", sizeText: DisplayText.bytes(model.dockerReclaimableBytes),
                             detail: "Unused containers, images and build cache. Volumes and tagged images are kept.", buttonTitle: "Clean up Docker…") {
                    Task { await model.beginDockerPrune() }
                }.disabled(!model.canPrune).help(model.pruneDisabledReason ?? "Review before cleaning")
                QueuedItemStatus(queue: model.app.cleanupQueue, resource: DockerSimulatorsModel.dockerResource)
                GroupedSection(title: "Docker usage") {
                    ForEach(model.dockerUsage.sorted { sort == .name ? $0.type < $1.type : usageBytes($0.type) > usageBytes($1.type) }) { line in
                        HStack { Text(line.type); Spacer(); Text(line.sizeText).monospacedDigit() }
                        Text("\(line.countText) · \(line.reclaimableText) reclaimable").font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = model.dockerReadFailure { Text(error).foregroundStyle(Palette.orange) }
                }
            }
            ForEach(model.dockerWarnings, id: \.self) { Text($0).foregroundStyle(Palette.orange) }
        }
    }
    private func usageBytes(_ type: String) -> Int64 {
        model.docker?.usage.first { $0.type == type }?.sizeBytes ?? -1
    }
    private var simulators: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.noXcode {
                GroupedSection(title: "Simulators") {
                    EmptyState(systemImage: "hammer", headline: "Xcode tools missing", line: "Install Xcode and select its command line tools to read simulators.")
                }
            } else {
                CategoryCard(systemImage: "iphone", title: "Simulators", sizeText: DisplayText.bytes(model.unavailableBytes),
                             detail: "\(model.unavailableDevices.count) unavailable devices. Installed runtimes and devices that can boot are kept.",
                             buttonTitle: "Delete unavailable simulators…") { Task { await model.beginSimulatorsDelete() } }
                    .disabled(!model.canDeleteUnavailable).help(model.deviceListFailure ?? "Review devices before deleting")
                QueuedItemStatus(queue: model.app.cleanupQueue, resource: DockerSimulatorsModel.simulatorsResource)
                GroupedSection(title: "Devices and runtimes") {
                    HStack { Text("Devices"); Spacer(); SizeText(bytes: model.devicesBytes) }
                    HStack { Text("Caches"); Spacer(); SizeText(bytes: model.cachesBytes) }
                    if model.unavailableDevices.isEmpty {
                        NothingLine(text: "No unavailable simulators to delete.")
                    }
                    ForEach(model.unavailableDevices.sorted { sort == .name ? $0.name < $1.name : ($0.sizeBytes ?? -1) > ($1.sizeBytes ?? -1) }) { device in
                        HStack { Text(device.name); Spacer(); SizeText(bytes: device.sizeBytes) }
                        Text(device.runtimeName).font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    Text("Installed runtimes").font(.subheadline.weight(.semibold))
                    ForEach((model.simulators?.runtimes ?? []).sorted { sort == .name ? $0.displayName < $1.displayName : ($0.sizeBytes ?? -1) > ($1.sizeBytes ?? -1) }) { runtime in
                        HStack { Text(runtime.displayName); Spacer(); SizeText(bytes: runtime.sizeBytes) }
                    }
                    Text(DockerSimulatorsModel.runtimesHint).font(.callout).foregroundStyle(.secondary)
                    if let error = model.deviceListFailure { Text(error).foregroundStyle(Palette.orange) }
                }
            }
            ForEach(model.simulatorWarnings, id: \.self) { Text($0).foregroundStyle(Palette.orange) }
        }
    }
}
