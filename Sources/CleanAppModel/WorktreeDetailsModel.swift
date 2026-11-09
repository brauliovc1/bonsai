import CleanCore
import Foundation
import Observation

/// The details panel's slower facts about one worktree: its last five commits and its upstream with
/// ahead/behind. Read only when the panel shows a row (`load(for:)`), never during the scan; kept until
/// another row, or a moved HEAD or branch, needs a fresh read. Read-only (`GitInfoReader`).
@MainActor
@Observable
public final class WorktreeDetailsModel {
    public static let commitCount = 5

    /// What was read for one worktree.
    public struct History: Equatable, Sendable {
        public var commits: [CommitSummary]
        /// nil when detached or without an upstream.
        public var upstream: UpstreamStatus?
        /// Why the upstream couldn't be read, when the commits could.
        public var upstreamError: String?
    }

    public enum State: Equatable, Sendable {
        case notLoaded
        case loading
        case loaded(History)
        case failed(String)
    }

    let git: Git?
    /// The row (`WorktreeRow.detailsKey`) the state belongs to.
    public private(set) var key: String?
    public private(set) var state: State = .notLoaded
    /// Reads started, for tests (each row is read once until its key changes).
    public private(set) var loadCount = 0

    public init(git: Git?) {
        self.git = git
    }

    /// The state for `row`: `.notLoaded` until `load(for:)` ran for it.
    public func state(for row: WorktreeRow) -> State {
        key == row.detailsKey ? state : .notLoaded
    }

    /// Reads the commits and the upstream of `row`, unless they are already read (or being read) for it.
    /// When another row is asked for meanwhile, this result is dropped.
    public func load(for row: WorktreeRow) async {
        let key = row.detailsKey
        if self.key == key, state != .notLoaded, !isFailed { return }
        self.key = key
        guard let git else {
            state = .failed("git not found")
            return
        }
        state = .loading
        loadCount += 1
        let reader = GitInfoReader(git: git)
        let worktree = row.worktree
        let result: State
        do {
            let commits = try await reader.recentCommits(of: worktree, count: Self.commitCount)
            var history = History(commits: commits)
            do {
                history.upstream = try await reader.upstream(of: worktree)
            } catch {
                history.upstreamError = "\(error)"
            }
            result = .loaded(history)
        } catch {
            result = .failed("\(error)")
        }
        guard self.key == key else { return }
        state = result
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }
}
