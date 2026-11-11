import CleanAppModel
import CleanCore
import SwiftUI

struct CompareView: View {
    @Bindable var model: CompareModel
    let navigation: NavigationModel
    var worktrees: WorktreesModel?
    @State private var change = 0

    var body: some View {
        VStack(spacing: 0) {
            CompareTopBar(model: model)
            if let snapshot = model.snapshot { CompareSummaryView(snapshot: snapshot) }
            BranchMapPanel(model: model.branches, navigation: navigation, worktrees: worktrees)
            Divider()
            HStack {
                Picker("Review", selection: $model.showsCommits) {
                    Text("Files").tag(false)
                    Text("Commits · \(model.snapshot?.range.commits.count ?? 0)").tag(true)
                }.pickerStyle(.segmented).fixedSize()
                Spacer()
                Text("\(model.viewedCount) of \(model.files.count) viewed").font(.callout).foregroundStyle(.secondary)
                Menu("Copy") {
                    Button("Copy file patch") { copyPatch(whole: false) }.disabled(model.selectedFile == nil)
                    Button("Copy whole patch") { copyPatch(whole: true) }.disabled(model.snapshot == nil)
                    Button("Copy summary") { FolderActions.copy([model.snapshot?.summary ?? ""]) }
                }.fixedSize()
            }.padding(.horizontal, 18).padding(.vertical, 10)
            Divider()
            if let problem = model.problem { ProblemBanner(text: problem) }
            if model.isLoading && model.snapshot == nil {
                Spacer(); ProgressView("Reading branches…"); Spacer()
            } else if model.snapshot == nil {
                EmptyState(systemImage: "arrow.left.arrow.right", headline: "Compare branches", line: "Choose a repo to review changes since two branches split.")
            } else {
                HSplitView {
                    if model.showsCommits { CompareCommitsView(model: model).frame(minWidth: 220, idealWidth: 270, maxWidth: 340) }
                    CompareFilesView(model: model).frame(minWidth: 220, idealWidth: 260, maxWidth: 360)
                    CompareDiffPane(model: model, change: change).frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("Compare")
        .task(id: navigation.compareRequest) {
            if let request = navigation.compareRequest {
                await model.configure(repo: request.repo, base: request.base, compare: request.compare)
            } else { await model.loadIfNeeded() }
        }
        .task(id: model.repositories) { await model.loadIfNeeded() }
        .background {
            Button("Refresh") { Task { await model.refresh() } }.keyboardShortcut("r").hidden()
            Button("Find in diff") { find() }.keyboardShortcut("f").hidden()
        }
        .onKeyPress(.downArrow) { reviewKey { Task { await model.moveFile(1) } } }
        .onKeyPress(.upArrow) { reviewKey { Task { await model.moveFile(-1) } } }
        .onKeyPress("n") { reviewKey { change += 1 } }
        .onKeyPress("p") { reviewKey { change -= 1 } }
        .onKeyPress(.space) {
            reviewKey { if let path = model.selectedPath { model.toggleViewed(path) } }
        }
    }

    private func reviewKey(_ action: () -> Void) -> KeyPress.Result {
        if let event = NSApp.currentEvent,
           !event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty { return .ignored }
        let window = NSApp.currentEvent?.window ?? NSApp.keyWindow
        if let editor = window?.firstResponder as? NSTextView, editor.isFieldEditor { return .ignored }
        action()
        return .handled
    }

    private func copyPatch(whole: Bool) {
        Task {
            do { FolderActions.copy([try await model.copyPatch(wholeCompare: whole)]) }
            catch { NSSound.beep() }
        }
    }
    private func find() {
        let item = NSMenuItem(); item.tag = NSTextFinder.Action.showFindInterface.rawValue
        NSApp.sendAction(#selector(NSTextView.performTextFinderAction(_:)), to: nil, from: item)
    }
}
