import CleanAppModel
import CleanCore
import SwiftUI

/// Remove anyway (PLAN §4.8): its own red sheet for one worktree. It first looks again, then lists every entry
/// that is deleted for good (paths middle-truncated, all reachable by scrolling), then the notes. The checkbox
/// enables the red button; Cancel is the default button, so Return and Esc both cancel. After the removal the
/// same sheet says what happened, or "It changed since you confirmed. Look again." with what changed.
struct RemoveAnywaySheet: View {
    @Bindable var model: WorktreesModel

    var body: some View {
        Group {
            if let outcome = model.removeAnywayOutcome {
                OutcomePage(outcome: outcome) { model.dismissRemoveAnyway() }
            } else if let confirmation = model.removeAnywayConfirmation {
                confirmPage(confirmation)
            } else if let refusal = model.removeAnywayRefusal {
                OutcomePage(title: "It can't be removed anyway now", text: refusal, tone: .orange) {
                    model.dismissRemoveAnyway()
                }
            } else {
                SheetProgress(text: "Looking at it again…") { model.dismissRemoveAnyway() }
            }
        }
        .padding(20)
        .frame(width: 620)
        .frame(minHeight: 300, idealHeight: 520, maxHeight: 720)
        .interactiveDismissDisabled(model.isRemovingAnyway)
    }

    private func confirmPage(_ confirmation: RemoveAnywayConfirmation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SheetHeading(title: "Remove 1 worktree (\(DisplayText.bytes(confirmation.assessment.estimatedBytes))) anyway?", subtitle: confirmation.title)
            Text(confirmation.line)
                .fontWeight(.medium)
                .foregroundStyle(Palette.orange)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                StatusChip(words: WorktreeStatusText.chip(for: confirmation.assessment))
                SizeText(bytes: confirmation.assessment.estimatedBytes, isMeasuring: false)
                    .foregroundStyle(.secondary)
                // As the rows show it (~/…); the full path in the tooltip.
                Text(TildePath.abbreviate(confirmation.worktree.path, home: model.app.environment.homeDirectory))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(confirmation.worktree.path)
            }
            .font(.callout)
            LossListView(list: confirmation.lossList, worktree: confirmation.worktree.url)
            Toggle(RemoveAnywayText.checkbox, isOn: $model.removeAnywayUnderstood)
                .toggleStyle(.checkbox)
                .disabled(model.isRemovingAnyway)
            buttons(confirmation)
        }
    }

    private func buttons(_ confirmation: RemoveAnywayConfirmation) -> some View {
        HStack {
            if model.isRemovingAnyway {
                ProgressView().controlSize(.small)
                Text("Checking once more, then removing…").foregroundStyle(.secondary)
            }
            Spacer()
            // Return and Esc both cancel: the hidden button takes Esc, Cancel itself is the default button.
            Button("Cancel") { model.dismissRemoveAnyway() }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isRemovingAnyway)
                .background {
                    Button("Cancel") { model.dismissRemoveAnyway() }
                        .keyboardShortcut(.cancelAction)
                        .opacity(0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .disabled(model.isRemovingAnyway)
                }
            Button(RemoveAnywayText.buttonTitle, role: .destructive) {
                model.queueRemoveAnyway(confirmation, understood: model.removeAnywayUnderstood)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.red)
            .disabled(!model.removeAnywayUnderstood || model.isRemovingAnyway)
            .help(model.removeAnywayUnderstood ? "Delete it and everything listed, for good" : "Tick the box first")
        }
    }
}

/// Every category with every entry, in one scrolling list: what is deleted first, then what is only listed. Files
/// use the details panel's row (`WorktreeFileRowView`), so both read the same.
struct LossListView: View {
    let list: LossList
    let worktree: URL

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(list.sections, id: \.category) { section in
                    Text(RemoveAnywayText.heading(section))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(section.category.isLost ? Palette.orange : Color.secondary)
                        .padding(.top, 8)
                    if let files = WorktreeFileRow.rows(for: section, in: worktree) {
                        ForEach(files) { file in
                            WorktreeFileRowView(file: file).padding(.horizontal, -10)
                        }
                    } else {
                        ForEach(Array(section.entries.enumerated()), id: \.offset) { _, entry in
                            EntryLine(entry: entry, detailBelow: section.category == .reposWithLocalWork
                                || section.category == .unreadableRepos || section.category == .claudeSession)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.stroke))
    }
}

/// One entry: the path (middle-truncated, in full in its tooltip) and what git or the check said about it.
private struct EntryLine: View {
    let entry: LossList.Entry
    let detailBelow: Bool

    var body: some View {
        if detailBelow {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.text).lineLimit(entry.detail == nil ? 4 : 1).truncationMode(.middle)
                if let detail = entry.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            .font(.callout)
            .help(entry.text + (entry.detail.map { "\n\($0)" } ?? ""))
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let detail = entry.detail {
                    Text(detail).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .font(.callout.monospaced())
            .help(entry.text + (entry.detail.map { " (\($0))" } ?? ""))
        }
    }
}

/// After the removal (or when the fresh look said no): what happened, and Close.
private struct OutcomePage: View {
    let title: String
    let text: String
    let tone: StatusTone
    var changes: [String] = []
    let close: () -> Void

    init(title: String, text: String, tone: StatusTone, close: @escaping () -> Void) {
        self.title = title
        self.text = text
        self.tone = tone
        self.close = close
    }

    init(outcome: RemoveAnywayOutcome, close: @escaping () -> Void) {
        switch outcome {
        case .removed(let result): (title, tone) = (CleanupPresentation.headline(result.freedBytes), .green)
        case .changed: (title, tone) = ("Nothing was removed", .orange)
        case .failed: (title, tone) = ("Nothing was removed", .orange)
        }
        text = outcome.text
        changes = outcome.changes
        self.close = close
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SheetHeading(title: title)
                .foregroundStyle(Palette.color(tone))
            Text(text).fixedSize(horizontal: false, vertical: true)
            if !changes.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                            Label(change, systemImage: "arrow.triangle.2.circlepath")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Close", action: close).keyboardShortcut(.defaultAction)
            }
        }
    }
}
