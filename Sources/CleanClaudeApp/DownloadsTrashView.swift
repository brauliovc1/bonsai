import AppKit
import CleanAppModel
import CleanCore
import SwiftUI

struct DownloadsTrashView: View {
    @Bindable var model: DownloadsTrashModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PageHeader(title: "Downloads & Trash", subtitle: "Old downloads can be put back until the Trash is emptied.") {
                        Button("Refresh") { Task { await model.refresh() } }.disabled(model.isScanning)
                    }
                    if model.isScanning && model.listing == nil { ProgressView("Looking in Downloads…") }
                    installers
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), alignment: .top)], alignment: .leading, spacing: 16) {
                        trashCard
                        snapshotsCard
                    }
                    if let snapshots = model.snapshots {
                        if snapshots.snapshots.isEmpty {
                            NothingLine(text: "No local snapshots")
                        } else {
                            GroupedSection(title: "Local snapshots") {
                                ForEach(snapshots.snapshots) { snapshot in
                                    Text(snapshot.date, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                                        .font(.callout).monospacedDigit()
                                }
                            }
                        }
                        if let purgeable = snapshots.purgeableBytes, purgeable > 0 {
                            NothingLine(text: "macOS can free up to \(DisplayText.bytes(purgeable)) by itself")
                        }
                    }
                    if model.automationDenied {
                        GroupedSection {
                            Text(TrashEmptyError.automationMessage).font(.callout)
                            Button("Open Automation settings") {
                                openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
                            }
                        }
                    }
                    ForEach(model.warnings, id: \.self) { ProblemBanner(text: $0) }
                }
                .padding(24)
            }
            if !model.selected.isEmpty {
                SelectionBar(text: "\(model.selected.count) selected · \(DisplayText.bytes(model.selectedBytes))") {
                    Button("Clear") { model.selection.removeAll() }
                    Button("Move to Trash…") { model.prepareMove() }.buttonStyle(.borderedProminent)
                }
            }
        }
        .sheet(item: $model.moveConfirmation) { confirmation in DownloadsMoveSheet(model: model, confirmation: confirmation) }
        .sheet(isPresented: $model.isShowingEmptySheet) { EmptyTrashSheet(model: model) }
        .task { await model.loadIfNeeded() }
    }

    private var installers: some View {
        GroupedSection(title: "Old installers and archives") {
            HStack {
                Text("Added at least 30 days ago · top level of Downloads only").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Select all") { model.selectAllReady() }.disabled(model.eligible.isEmpty)
            }
            if model.files.isEmpty {
                EmptyState(systemImage: "arrow.down.doc", headline: "No old installers or archives",
                           line: "Recent downloads, folders, apps and other files stay where they are.")
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(model.files) { file in
                    if file.id != model.files.first?.id { Divider() }
                    row(file)
                }
            }
        }
    }

    private func row(_ file: DownloadFile) -> some View {
        HStack(spacing: 12) {
            Toggle("Select \(file.name)", isOn: Binding(get: { model.selection.contains(file.id) },
                                                       set: { model.setSelected(file, $0) }))
                .labelsHidden().toggleStyle(.checkbox)
                .disabled(!file.canMove || model.app.cleanupQueue.task(for: file.path) != nil)
            VStack(alignment: .leading, spacing: 4) {
                Text(file.name).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Text("Added \(file.addedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(DisplayText.bytes(file.bytes)).font(.callout).monospacedDigit()
            if model.app.cleanupQueue.task(for: file.path) != nil {
                QueuedItemStatus(queue: model.app.cleanupQueue, resource: file.path)
            } else {
                StatusChip(words: StatusWords(file.skipReason ?? "Can move to Trash", file.canMove ? .green : .grey))
            }
        }
        .help(file.path)
    }

    private var trashCard: some View {
        GroupedSection(title: "Trash") {
            if let trash = model.trash, let bytes = trash.bytes, let count = trash.count {
                Text(DisplayText.bytes(bytes)).font(.title2.weight(.semibold)).monospacedDigit()
                Text("\(count) \(count == 1 ? "item" : "items") · emptying Trash permanently deletes its contents")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text(model.listing == nil ? "Not measured yet" : TrashInfo.unreadableMessage)
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button(model.isPreparingEmptyTrash ? "Checking Trash…" : "Empty Trash…") {
                Task { await model.prepareEmptyTrash() }
            }.disabled(!model.canEmptyTrash)
        }
    }

    private var snapshotsCard: some View {
        CategoryCard(systemImage: "clock.arrow.circlepath", title: "Time Machine",
                     sizeText: model.snapshots.map { "\($0.snapshots.count) local snapshots" } ?? "Not measured yet",
                     detail: "macOS removes local snapshots by itself when space runs low.",
                     buttonTitle: "Open Time Machine settings", tone: .blue) {
            openSettings("x-apple.systempreferences:com.apple.Time-Machine-Settings.extension")
        }
    }

    private func openSettings(_ value: String) { if let url = URL(string: value) { NSWorkspace.shared.open(url) } }
}
