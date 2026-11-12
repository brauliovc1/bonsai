import CleanAppModel
import SwiftUI

/// The Overview (PLAN §8.3): free space and what Bonsai can free, the bar, a card per category with something
/// to free (largest first) whose button opens its screen filtered to what it counted, one line for the empty
/// categories, and the auto clean row.
struct OverviewView: View {
    let model: OverviewModel
    let settings: SettingsModel
    var quickClean: QuickCleanModel? = nil
    var openBranches: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            TestModeBanner(app: model.app)
            LaunchNoticeBanner(app: model.app)
            ScrollView {
                content
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                    .frame(maxWidth: 940, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Overview")
        .toolbar {
            ToolbarItemGroup {
                if let openBranches {
                    Button(action: openBranches) {
                        Label("View branches", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .labelStyle(.titleAndIcon)
                    .disabled(model.app.scan?.worktrees.isEmpty != false)
                    .help(model.app.scan?.worktrees.isEmpty != false
                        ? "Scan a repository first to view its branches."
                        : "Open the branch timeline, distances and history")
                }
                Button { Task { await model.refresh() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .labelStyle(.titleAndIcon)
                .help("Measure everything again (⌘R)")
                .keyboardShortcut("r")
                .disabled(model.isRefreshing)
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let problem = model.app.problem {
                ProblemBanner(text: problem)
            }
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 16) { reclaimHeading; Spacer(minLength: 12); quickCleanAction }
                    VStack(alignment: .leading, spacing: 12) { reclaimHeading; quickCleanAction }
                }
                if quickClean != nil {
                    Text("Worktrees and project dependencies inactive for **7+ days**, plus eligible caches and old installers.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Quick clean checks its own eligible items. The preview shows the exact total.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Divider()
                Text(model.headline).font(.body.weight(.medium)).monospacedDigit().foregroundStyle(headlineColor)
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                if let space = model.space { SpaceBar(space: space, level: model.level) }
            }
            cards
            lines
            AutoCleanRow(line: model.autoClean, settings: settings)
            Text(SizeText.estimateHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var reclaimHeading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.canFreeText)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(model.canFreeSomething ? Palette.green : .primary)
                .fixedSize(horizontal: false, vertical: true)
            if let measuring = model.measuringText {
                HStack(spacing: 5) { ProgressView().controlSize(.mini); Text(measuring) }
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var quickCleanAction: some View {
        if let quickClean {
            Button { Task { await quickClean.begin() } } label: { Label("Quick clean…", systemImage: "sparkles") }
                .buttonStyle(.borderedProminent).controlSize(.large).fixedSize()
                .disabled(quickClean.isPreparing || model.app.isQuitting)
                .help("Review the exact items and total before confirming cleanup")
        }
    }

    @ViewBuilder
    private var cards: some View {
        let cards = model.cards
        if cards.isEmpty, model.measuringText == nil {
            EmptyState(systemImage: "checkmark.circle", headline: "Nothing to clean",
                       line: "Bonsai found nothing it can free right now. It looks again after every scan.")
                .frame(maxWidth: .infinity)
        } else if !cards.isEmpty {
            GroupedSection(title: "Review by category") {
                VStack(spacing: 0) {
                    ForEach(cards) { card in
                        CategorySummaryRow(systemImage: card.category.systemImage, title: card.title,
                                           amount: card.sizeText, detail: card.detail) { model.open(card.category) }
                        if card.id != cards.last?.id { Divider() }
                    }
                }
            }
            if cards.contains(where: { $0.category == .downloads }) {
                Text("Downloads move to Trash. Their space is freed only when Trash is emptied.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var lines: some View {
        // With no card at all the empty state says it; the line would only list every category.
        let nothing = model.cards.isEmpty ? nil : model.nothingText
        if nothing != nil || model.notCountedText != nil {
            VStack(alignment: .leading, spacing: 6) {
                if let nothing {
                    NothingLine(text: nothing)
                }
                if let notCounted = model.notCountedText {
                    Label(notCounted, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// "Macintosh HD · Scanned 3 minutes ago".
    private var subtitle: String {
        var parts: [String] = []
        if let volume = model.disk.volumeName { parts.append(volume) }
        if model.app.isScanning {
            parts.append(DisplayText.progress(model.app.progress))
        } else if let scanned = model.app.lastScanAt {
            parts.append("Scanned \(scanned.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }

    private var headlineColor: Color {
        switch model.level {
        case .low: Palette.orange
        case .veryLow: Palette.red
        case .normal, .unknown: .primary
        }
    }
}
