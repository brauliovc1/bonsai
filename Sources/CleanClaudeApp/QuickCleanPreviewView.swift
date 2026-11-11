import CleanAppModel
import SwiftUI

/// Shared with fixture renders so previews never need executable cleanup jobs.
struct QuickCleanPreviewView: View {
    let preview: QuickCleanPreview
    let canConfirm: Bool
    var problem: String? = nil
    var disabledReason: String? = nil
    let refresh: () -> Void
    let confirm: () -> Void
    let cancel: () -> Void
    @State private var expanded: Set<QuickCleanGroup.Kind> = []

    init(preview: QuickCleanPreview, canConfirm: Bool, problem: String? = nil, disabledReason: String? = nil,
         refresh: @escaping () -> Void = {},
         initiallyExpanded: Set<QuickCleanGroup.Kind> = [], confirm: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.preview = preview; self.canConfirm = canConfirm; self.problem = problem
        self.disabledReason = disabledReason; self.refresh = refresh
        self.confirm = confirm; self.cancel = cancel
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeading(title: "Quick clean", subtitle: "Review what will happen, then clean these items together.")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summary
                    if let problem { ProblemBanner(text: problem) }
                    ForEach(Array(preview.warnings.enumerated()), id: \.offset) { _, warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(Palette.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if preview.itemCount == 0 {
                        EmptyState(systemImage: "checkmark.circle", headline: "Nothing to clean right now",
                                   line: "No items meet the age and safety checks.")
                            .frame(maxWidth: .infinity)
                    }
                    GroupedSection(title: "Categories") {
                        ForEach(preview.groups) { group in
                            QuickCleanGroupView(group: group, isExpanded: Binding(
                                get: { expanded.contains(group.id) },
                                set: { if $0 { expanded.insert(group.id) } else { expanded.remove(group.id) } }
                            ))
                        }
                    }
                    Text(hasCleanupItems ? "Freed space is measured after cleaning and can be lower than these estimates. Existing Trash and Time Machine snapshots are left alone." : "Existing Trash and Time Machine snapshots are left alone.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            if !cleanupNotice.isEmpty {
                Text(cleanupNotice).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !canConfirm, preview.itemCount > 0, let disabledReason {
                Label(disabledReason, systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(preview.itemCount == 0 ? "Done" : "Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                if !canConfirm, preview.itemCount > 0 {
                    Button("Refresh preview", action: refresh)
                }
                Spacer()
                if preview.itemCount > 0 {
                    Button("Clean \(preview.itemCount) \(preview.itemCount == 1 ? "item" : "items")", role: .destructive, action: confirm)
                        .buttonStyle(.borderedProminent).tint(Palette.red)
                        .disabled(!canConfirm)
                        .help(disabledReason ?? "Queue exactly the items in this preview. Each item is checked again before it is cleaned.")
                }
            }
        }.padding(24)
    }

    private var hasCleanupItems: Bool { preview.groups.contains { $0.id != .downloads && !$0.items.isEmpty } }

    private var cleanupNotice: String {
        let hasCleanup = hasCleanupItems
        let hasDownloads = preview.groups.contains { $0.id == .downloads && !$0.items.isEmpty }
        if !hasCleanup {
            return hasDownloads ? "Only the listed downloads move to Trash. They can be put back while they remain there; existing Trash is not emptied." : ""
        }
        let permanent = "Listed cache, dependency, build, Docker and simulator data is deleted permanently. Worktree branches are kept; cleaning project folders keeps source files."
        return permanent + (hasDownloads ? " Listed downloads move to Trash." : "")
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estimated cleanup").font(.caption).foregroundStyle(.secondary)
                    Text(reclaimEstimate).font(.title2.weight(.semibold)).foregroundStyle(Palette.green)
                }
                Spacer()
                if let downloads = preview.groups.first(where: { $0.id == .downloads }), !downloads.items.isEmpty {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Move to Trash").font(.caption).foregroundStyle(.secondary)
                        Text(CleanupPresentation.estimate(downloads.items.map(\.estimatedBytes)))
                            .font(.title3.weight(.medium)).monospacedDigit()
                    }
                }
            }
            Text("Worktrees and project dependencies: idle for at least 7 days. Other age and safety checks stay the same.")
                .font(.callout).foregroundStyle(.secondary)
            if preview.groups.contains(where: { $0.id == .downloads && !$0.items.isEmpty }) {
                Text("Downloads move to the Trash. They free no space now; space is freed only when the Trash is emptied.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var reclaimEstimate: String {
        let sizes = preview.groups.filter { $0.id != .downloads }.flatMap(\.items).map(\.estimatedBytes)
        return sizes.isEmpty ? "Nothing eligible" : CleanupPresentation.estimate(sizes)
    }
}
