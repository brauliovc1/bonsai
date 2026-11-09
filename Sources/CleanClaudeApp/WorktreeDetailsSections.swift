import CleanAppModel
import CleanCore
import SwiftUI

/// Repo, branch or detached HEAD, upstream with ahead/behind, and the repo's remotes in full.
struct RepoBranchDetails: View {
    let row: WorktreeRow
    let state: WorktreeDetailsModel.State

    var body: some View {
        DetailLine("Repo", "\(row.repoName) (\(row.repoFolderText))")
        DetailLine(row.worktree.isDetached ? "HEAD" : "Branch", row.branchText)
        if !row.worktree.isDetached, !row.worktree.isBare {
            DetailLine("Upstream", upstreamText)
        }
        if row.remotes.isEmpty {
            DetailLine("Remote", "none")
        } else {
            ForEach(row.remotes, id: \.self) { remote in
                DetailLine(remote.name, remote.url + (remote.pushURL.map { "\npush: \($0)" } ?? ""))
            }
        }
    }

    private var upstreamText: String {
        switch state {
        case .notLoaded, .loading: return "…"
        case .failed: return "couldn't be read"
        case .loaded(let history):
            if let error = history.upstreamError { return "couldn't be read: \(error)" }
            guard let upstream = history.upstream else { return "none" }
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
            Text("Couldn't read the commits: \(message)").font(.callout).foregroundStyle(.red)
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

/// Idle days and each signal with its date (PLAN §4.3), or why there is no idle time.
struct IdleDetails: View {
    let row: WorktreeRow

    var body: some View {
        if row.worktree.isMain {
            Text("Not tracked for the main checkout (it is never removed).").font(.callout).foregroundStyle(.secondary)
        } else {
            DetailLine("Idle", row.idleDays.map { $0 == 1 ? "1 day" : "\($0) days" } ?? "unknown")
            ForEach(row.idleSignals, id: \.signal) { signal, date in
                DetailLine(signal.label.prefix(1).uppercased() + signal.label.dropFirst(), DisplayText.date(date))
            }
            if row.assessment.idle.capHit {
                Text("The file walk stopped at its limit, so the idle time is unknown.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(row.assessment.idle.errors, id: \.self) { error in
                Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        }
    }
}

/// The badge, the Claude warning for a Claude worktree, and every reason as P2 words it.
struct StatusDetails: View {
    let row: WorktreeRow

    var body: some View {
        StatusCell(row: row)
        if row.kind == .claude {
            Label(SafetyReason.claudeSessionWarning, systemImage: "exclamationmark.bubble")
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
        if row.reasons.isEmpty {
            Text("Nothing keeps auto mode away from it.").font(.callout).foregroundStyle(.secondary)
        }
        ForEach(Array(row.reasons.enumerated()), id: \.offset) { _, reason in
            if reason != .claudeSession {
                VStack(alignment: .leading, spacing: 1) {
                    Text(reason.label).font(.callout.weight(.medium))
                    Text(reason.sentence)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
