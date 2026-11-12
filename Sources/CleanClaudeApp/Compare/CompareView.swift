import CleanAppModel
import CleanCore
import SwiftUI

struct CompareView: View {
    @Bindable var model: CompareModel
    let navigation: NavigationModel
    var worktrees: WorktreesModel?
    @State private var change = 0

    var body: some View {
        // The viewport owns layout, regardless of the selected screen's ideal content size.
        GeometryReader { geometry in
            content(height: geometry.size.height)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
            .navigationTitle("Compare")
            .task(id: navigation.compareRequest) {
                if let request = navigation.compareRequest {
                    await model.configure(repo: request.repo, base: request.base, compare: request.compare)
                } else { await model.loadIfNeeded() }
            }
            .task(id: model.repositories) { await model.loadIfNeeded() }
            .background {
                Button("Refresh") { refresh() }.keyboardShortcut("r").hidden()
                Button("Find in diff") { find() }.keyboardShortcut("f").hidden()
            }
            .onKeyPress(.downArrow) { reviewKey { Task { await model.moveFile(1) } } }
            .onKeyPress(.upArrow) { reviewKey { Task { await model.moveFile(-1) } } }
            .onKeyPress("n") { reviewKey { change += 1 } }
            .onKeyPress("p") { reviewKey { change -= 1 } }
            .onKeyPress(.space) { reviewKey { if let path = model.selectedPath { model.toggleViewed(path) } } }
    }

    private func content(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            CompareTopBar(model: model)
            if let snapshot = model.snapshot { CompareSummaryView(snapshot: snapshot) }
            if let problem = model.problem { ProblemBanner(text: problem) }
            if model.repository == nil {
                EmptyState(systemImage: "arrow.left.arrow.right", headline: "Compare branches",
                           line: model.repositories.isEmpty ? "Scan a repository to compare its branches." : "Choose a repository to review changes since two branches split.",
                           actionTitle: model.repositories.isEmpty ? "Refresh repositories" : nil,
                           action: { model.app.requestRefresh() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.isLoading && model.snapshot == nil {
                ProgressView("Reading branches…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.snapshot == nil {
                EmptyState(systemImage: "exclamationmark.triangle", headline: "Comparison unavailable",
                           line: "Choose another branch or refresh to try again.", actionTitle: "Try again", action: refresh)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.branches.isFocused {
                Divider()
                BranchMapPanel(model: model.branches, navigation: navigation, worktrees: worktrees, focused: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                BranchMapPanel(model: model.branches, navigation: navigation, worktrees: worktrees)
                Divider()
                workspaceBar
                Divider()
                workspace
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: model.branches.isOpen) { _, open in
            if open && height < 620 { model.branches.isFocused = true }
        }
    }

    private var workspace: some View {
        GeometryReader { viewport in
            // Bound the two navigation columns to their allocation. Native HSplitView's ideal widths can
            // expand past its navigation column at compact sizes, even when both children use flexible frames.
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if model.showsCommits {
                        VStack(spacing: 0) {
                            CompareCommitsView(model: model).frame(height: min(180, max(90, viewport.size.height * 0.38)))
                            Divider()
                            CompareFilesView(model: model).frame(maxHeight: .infinity)
                        }
                    } else { CompareFilesView(model: model) }
                }.frame(width: min(260, max(180, viewport.size.width * 0.32)))
                Divider()
                CompareDiffPane(model: model, change: change)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
        }
    }

    private var workspaceBar: some View {
        HStack(spacing: 12) {
            Picker("Review", selection: $model.showsCommits) {
                Text("Files").tag(false)
                Text("Commits · \(model.snapshot?.range.commits.count ?? 0)").tag(true)
            }.labelsHidden().pickerStyle(.segmented).fixedSize()
            Spacer(minLength: 0)
            Text("\(model.viewedCount) of \(model.files.count) viewed").font(.caption).foregroundStyle(.secondary)
            Menu("Copy") {
                Button("Copy file patch") { copyPatch(whole: false) }.disabled(model.selectedFile == nil)
                Button("Copy whole patch") { copyPatch(whole: true) }
                Button("Copy summary") { FolderActions.copy([model.snapshot?.summary ?? ""]) }
            }.fixedSize()
        }.padding(.horizontal, 16).padding(.vertical, 8)
    }

    private func refresh() { Task { await model.refresh() } }
    private func reviewKey(_ action: () -> Void) -> KeyPress.Result {
        if let event = NSApp.currentEvent,
           !event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty { return .ignored }
        let window = NSApp.currentEvent?.window ?? NSApp.keyWindow
        if let editor = window?.firstResponder as? NSTextView, editor.isFieldEditor { return .ignored }
        guard !model.branches.isFocused else { return .ignored }
        action(); return .handled
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
