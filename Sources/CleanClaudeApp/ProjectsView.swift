import CleanAppModel
import CleanCore
import SwiftUI

struct ProjectsView: View {
    @Bindable var model: ProjectsModel
    let navigation: NavigationModel
    @State private var sort: ContentSort = .size

    var body: some View {
        VStack(spacing: 0) {
            TestModeBanner(app: model.app)
            PageHeader(title: "Project folders", subtitle: "Dependencies and build output you can get back when needed.") {
                Button("Clean selected…") { Task { await model.beginClean() } }.disabled(!model.canClean)
            }.padding(20)
            if let problem = model.app.problem { ProblemBanner(text: problem) }
            HStack {
                Picker("Show projects", selection: $model.filter) {
                    if model.filter == .canFree {
                        Text("Ready to clean · \(model.idleTotal.count)").tag(ProjectsModel.Filter.canFree)
                    }
                    Text("Idle \(model.threshold)+ days · \(model.allRows.count { ($0.idleDays ?? -1) >= model.threshold })")
                        .tag(ProjectsModel.Filter.idle)
                    Text("All · \(model.allRows.count)").tag(ProjectsModel.Filter.all)
                }.pickerStyle(.segmented).frame(maxWidth: 470)
                Spacer()
                Button("Select all idle") { model.selectAllIdle() }.disabled(model.idleTotal.count == 0)
                Button("Refresh") { Task { await model.refreshAll() } }.disabled(model.isScanning || model.app.isScanning)
            }.padding(.horizontal, 20).padding(.bottom, 8)
            ContentSortBar(selection: $sort, showsActivity: true)
                .onChange(of: sort) { _, value in
                    switch value {
                    case .size: model.sortOrder = [KeyPathComparator(\ProjectTableItem.sizeSortKey, order: .reverse)]
                    case .activity: model.sortOrder = [KeyPathComparator(\ProjectTableItem.idleSortKey, order: .reverse)]
                    case .name: model.sortOrder = [KeyPathComparator(\ProjectTableItem.nameSortKey)]
                    }
                }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if model.report == nil {
                        ProgressView(ProjectsFooter.progressText(model)).frame(maxWidth: .infinity).padding(30)
                    } else if model.rows.isEmpty {
                        EmptyState(systemImage: "cube.box", headline: model.allRows.isEmpty ? "No project folders found" : "Nothing idle",
                                   line: model.allRows.isEmpty ? "No dependencies or build folders were found in your projects." : "No project has been idle \(model.threshold) days. All shows the other projects.",
                                   actionTitle: model.allRows.isEmpty ? nil : "Show all", action: { model.filter = .all })
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(model.groups) { group in
                        GroupedSection {
                            Button { model.toggleExpanded(group.repoPath) } label: {
                                HStack {
                                    Image(systemName: model.isExpanded(group.repoPath) ? "chevron.down" : "chevron.right")
                                    Text(group.name).fontWeight(.semibold)
                                    Text(group.countText).foregroundStyle(.secondary)
                                    Spacer()
                                    SizeText(bytes: group.rows.reduce(Int64(0)) { $0 + $1.sizeBytes }, hasUnknownParts: group.rows.contains { $0.project.hasUnknownSizes })
                                }
                            }.buttonStyle(.plain).help(group.folderText)
                            if model.isExpanded(group.repoPath) {
                                ForEach(group.rows) { row in
                                    Divider()
                                    ProjectFolderRow(model: model, row: row)
                                }
                            }
                        }
                    }
                }.padding(20)
            }
            ProjectsFooter(model: model) { navigation.show(.worktrees) }
            if !model.selectedRows.isEmpty {
                SelectionBar(text: "\(model.selectedRows.count) selected · \(DisplayText.bytes(model.selectedRows.reduce(Int64(0)) { $0 + $1.sizeBytes }))") {
                    Button("Clean selected…") { Task { await model.beginClean() } }.disabled(!model.canClean)
                }
            }
        }
        .navigationTitle("Project folders")
        .sheet(isPresented: $model.isShowingCleanSheet, onDismiss: { model.dismissClean() }) { ProjectsCleanSheet(model: model) }
        .task { await model.loadIfNeeded() }
    }
}
