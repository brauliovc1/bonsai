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
            CleanupPageHeader(subtitle: "Dependencies and build output can be restored when needed. Source files stay.")
            if let problem = model.app.problem { ProblemBanner(text: problem) }
            ViewThatFits(in: .horizontal) {
                HStack { projectFilter.labelsHidden().pickerStyle(.segmented).fixedSize(); Spacer(minLength: 8); selectIdle }
                HStack { projectFilter.pickerStyle(.menu); Spacer(minLength: 8); selectIdle }
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
                                    Text(CleanupPresentation.estimate(group.rows.flatMap { $0.project.folders }.map(\.bytes))).monospacedDigit()
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
                SelectionBar(text: "\(model.selectedRows.count) selected · \(CleanupPresentation.estimate(model.selectedRows.flatMap { $0.project.folders }.map(\.bytes)))") {
                    Button("Clear") { model.selection.removeAll() }
                    Button("Clean selected…") { Task { await model.beginClean() } }.disabled(!model.canClean)
                }
            } else {
                SelectionBar(text: "Select projects to review cleanup") { EmptyView() }
            }
        }
        .navigationTitle("Project folders")
        .toolbar {
            Button { Task { await model.refreshAll() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .keyboardShortcut("r").disabled(model.isScanning || model.app.isScanning)
        }
        .sheet(isPresented: $model.isShowingCleanSheet, onDismiss: { model.dismissClean() }) { ProjectsCleanSheet(model: model) }
        .task { await model.loadIfNeeded() }
    }
    private var projectFilter: some View {
        Picker("Show projects", selection: $model.filter) {
            if model.filter == .canFree { Text("Ready to clean · \(model.idleTotal.count)").tag(ProjectsModel.Filter.canFree) }
            Text("Idle \(model.threshold)+ days · \(model.allRows.count { ($0.idleDays ?? -1) >= model.threshold })").tag(ProjectsModel.Filter.idle)
            Text("All · \(model.allRows.count)").tag(ProjectsModel.Filter.all)
        }
    }
    private var selectIdle: some View {
        Button("Select all idle") { model.selectAllIdle() }.disabled(model.idleTotal.count == 0).fixedSize()
    }

}
