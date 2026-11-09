import CleanAppModel
import CleanCore
import SwiftUI

/// A titled block of the details panel.
struct DetailsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content
        }
    }
}

/// "Label    value", the value any view.
struct DetailRow<Value: View>: View {
    let label: String
    @ViewBuilder let value: Value

    init(_ label: String, @ViewBuilder value: () -> Value) {
        self.label = label
        self.value = value()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).foregroundStyle(.secondary).frame(width: 96, alignment: .leading)
            value.frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
    }
}

/// "Label    value", the value selectable text.
struct DetailLine: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        DetailRow(label) {
            Text(value).textSelection(.enabled).lineLimit(3)
        }
    }
}

/// Repo folder, branch or detached HEAD, upstream with ahead/behind, and the repo's remotes in full.
struct RepoBranchDetails: View {
    let row: WorktreeRow
    let state: WorktreeDetailsModel.State

    var body: some View {
        DetailLine("Repo folder", row.repoFolderText)
        DetailLine(row.worktree.isDetached ? "Commit" : "Branch", row.branchText)
        if !row.worktree.isDetached, !row.worktree.isBare {
            DetailLine("Upstream", upstreamText)
        }
        if row.remotes.isEmpty {
            DetailLine("Remote", "None")
        } else {
            ForEach(row.remotes, id: \.self) { remote in
                DetailLine(remote.name, remote.url + (remote.pushURL.map { "\npush: \($0)" } ?? ""))
            }
        }
    }

    private var upstreamText: String {
        switch state {
        case .notLoaded, .loading: return "…"
        case .failed: return "Couldn't be read"
        case .loaded(let history):
            if let error = history.upstreamError { return "Couldn't be read: \(error)" }
            guard let upstream = history.upstream else { return "None" }
            if upstream.isGone { return "\(upstream.name) (gone from the remote)" }
            var parts: [String] = []
            if upstream.ahead > 0 { parts.append("\(upstream.ahead) ahead") }
            if upstream.behind > 0 { parts.append("\(upstream.behind) behind") }
            let distance = parts.isEmpty ? "up to date" : parts.joined(separator: ", ")
            return "\(upstream.name), \(distance) (as of the last fetch)"
        }
    }
}

/// The last five commits: subject, then "3d ago · author".
struct RecentCommitsDetails: View {
    let row: WorktreeRow
    let state: WorktreeDetailsModel.State

    var body: some View {
        switch state {
        case .notLoaded, .loading:
            ProgressView().controlSize(.small)
        case .failed(let message):
            Text("Couldn't read the commits: \(message)").font(.callout).foregroundStyle(.secondary)
        case .loaded(let history):
            if history.commits.isEmpty {
                Text("No commits").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(history.commits, id: \.sha) { commit in
                VStack(alignment: .leading, spacing: 1) {
                    Text(commit.subject).font(.callout).lineLimit(2)
                    Text("\(DisplayText.ago(commit.date, now: row.now)) · \(commit.author) · \(commit.shortSHA)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .help("\(commit.message)\n\n\(DisplayText.commitByline(commit))")
            }
        }
    }
}

/// When it was last used and each sign of it with its date (PLAN §4.3), or why that is unknown.
struct IdleDetails: View {
    let row: WorktreeRow

    var body: some View {
        DetailLine("Last activity", row.activityText)
        ForEach(row.idleSignals, id: \.signal) { signal, date in
            DetailLine(signal.label.prefix(1).uppercased() + signal.label.dropFirst(), DisplayText.date(date))
        }
        if row.assessment.idle.capHit {
            Text("The folder has too many files to check them all, so its last activity is unknown.")
                .font(.caption).foregroundStyle(.secondary)
        }
        ForEach(row.assessment.idle.errors, id: \.self) { error in
            Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(3)
        }
    }
}

/// Every reason the verdict lists, in the app's words: what it is, then what it means.
struct ReasonsDetails: View {
    let row: WorktreeRow

    var body: some View {
        ForEach(Array(row.reasons.enumerated()), id: \.offset) { _, reason in
            if reason != .claudeSession {
                let words = WorktreeStatusText.words(for: reason)
                VStack(alignment: .leading, spacing: 2) {
                    Text(words.text)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(words.tone == .grey ? Color.primary : Palette.color(words.tone))
                    Text(WorktreeStatusText.sentence(for: reason))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
