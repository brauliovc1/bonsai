import CleanAppModel
import SwiftUI

/// The Claude usage screen. Read-only: it shows where Claude's own data takes space and points to Claude's
/// own Storage settings. Its only button is Refresh.
struct ClaudeUsageView: View {
    let model: ClaudeUsageModel
    @State private var sort: ContentSort = .size

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "Claude usage", subtitle: "See where Claude stores its data.") {
                    Button("Refresh") { Task { await model.refresh() } }.disabled(model.isScanning)
                }
                GroupedSection { Label(ClaudeUsageModel.note, systemImage: "info.circle").foregroundStyle(Palette.blue) }
                ContentSortBar(selection: $sort)
                if model.report == nil {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Measuring Claude's folders…").foregroundStyle(.secondary)
                    }
                } else {
                    if model.report?.totalBytes == 0 {
                        EmptyState(systemImage: "sparkles", headline: "No Claude data found", line: "Claude's folders appear here after you use it.")
                            .frame(maxWidth: .infinity)
                    }
                    GroupedSection { totals }
                    GroupedSection { transcripts }
                    GroupedSection { versions }
                    GroupedSection { desktop }
                    ForEach(model.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(Palette.orange)
                    }
                }
                HStack(spacing: 10) {
                    if model.isScanning {
                        ProgressView().controlSize(.small)
                    }
                    if let date = model.lastScanAt {
                        Text("Scanned \(date, format: .relative(presentation: .named))").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Claude usage")
        .task { if model.report == nil { await model.refresh() } }
    }

    private var totals: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Claude's data").font(.title3.weight(.semibold))
                Spacer()
                Text(model.totalText).font(.title3.weight(.semibold)).monospacedDigit()
            }
            ForEach(model.summaryLines.sorted { sort == .name ? $0.title < $1.title : $0.bytes > $1.bytes }) { line in
                HStack(alignment: .firstTextBaseline) {
                    Text(line.title)
                    if let detail = line.detail {
                        Text(detail).foregroundStyle(.secondary)
                    }
                    Spacer()
                    SizeText(bytes: line.bytes)
                }
            }
        }
    }

    private var transcripts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Largest transcript folders").font(.headline)
            if model.transcriptRows.isEmpty {
                Text("No transcripts found.").foregroundStyle(.secondary)
            }
            ForEach(model.transcriptRows.sorted { sort == .name ? $0.title < $1.title : $0.bytes > $1.bytes }) { row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.title)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help([row.project.folderName, row.note].compactMap { $0 }.joined(separator: "\n"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if row.folderGone {
                        StatusChip(words: StatusWords("Folder gone", .grey))
                            .help("The project this transcript folder belongs to no longer exists")
                    }
                    SizeText(bytes: row.bytes)
                }
            }
        }
    }

    private var versions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude Code versions").font(.headline)
            if model.versionNames.isEmpty {
                Text("None installed here.").foregroundStyle(.secondary)
            } else {
                Text(model.versionNames.joined(separator: ", ")).foregroundStyle(.secondary)
            }
        }
    }

    private var desktop: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude desktop app: largest items").font(.headline)
            if model.desktopRows.isEmpty {
                Text("No desktop app data found.").foregroundStyle(.secondary)
            }
            ForEach(model.desktopRows.sorted { sort == .name ? $0.title < $1.title : $0.bytes > $1.bytes }) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.title)
                    Spacer()
                    SizeText(bytes: row.bytes)
                }
            }
        }
    }
}
