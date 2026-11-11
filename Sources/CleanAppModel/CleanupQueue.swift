import CleanCore
import Foundation
import Observation

/// One FIFO per app. The existing guard and cross-process lock cover one complete task at a time.
@MainActor
@Observable
public final class CleanupQueue {
    public internal(set) var tasks: [CleanupTask] = []
    public var selectedTask: CleanupTask?
    public internal(set) var toasts: [CleanupToast] = []
    public var windowIsVisible = false
    @ObservationIgnored unowned let app: AppModel
    @ObservationIgnored var jobs: [UUID: Job] = [:]
    @ObservationIgnored var runner: Task<Void, Never>?
    @ObservationIgnored var emptyWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored var sleep: @MainActor (Duration) async -> Void = { duration in
        try? await Task.sleep(for: duration, clock: SuspendingClock())
    }
    @ObservationIgnored var toastSleep: @MainActor () async -> Void = {
        try? await Task.sleep(for: .seconds(6), clock: SuspendingClock())
    }
    @ObservationIgnored var notify: @MainActor (CleanupTask) async -> Void = { _ in }

    struct Job {
        let work: [CleanupWork]
        let finish: @MainActor (CleanupTask) async -> Void
    }

    init(app: AppModel) { self.app = app }
    public var pending: [CleanupTask] { tasks.filter(\.isPending) }
    public var hasPending: Bool { !pending.isEmpty }
    public var current: CleanupTask? { pending.first }
    public var queuedCount: Int { pending.count { $0.state == .queued || $0.state == .waiting } }
    public var activityText: String? {
        guard let task = current else { return nil }
        let line: String
        switch task.state {
        case .running: line = task.progressText
        case .waiting: line = "Waiting · another cleanup is running"
        default: line = "Queued · \(task.title)"
        }
        let more = pending.count - 1
        return line + (more > 0 ? " · \(more) waiting" : "")
    }

    /// Reject the whole submission if any confirmed resource overlaps another pending task.
    @discardableResult
    func enqueue(title: String, unit: String, work: [CleanupWork],
                 finish: @escaping @MainActor (CleanupTask) async -> Void = { _ in }) -> CleanupTask? {
        guard !app.isQuitting, !work.isEmpty else { return nil }
        let resources = work.flatMap { $0.item.resources }
        guard !resources.contains(where: { self.task(for: $0) != nil }) else { return nil }
        for index in work.indices {
            let previous = work[..<index].flatMap { $0.item.resources }
            guard !work[index].item.resources.contains(where: { resource in
                previous.contains { Self.overlaps($0, resource) }
            }) else { return nil }
        }
        let task = CleanupTask(title: title, unit: unit, items: work.map(\.item))
        tasks.append(task)
        jobs[task.id] = Job(work: work, finish: finish)
        if runner == nil { runner = Task { await drain() } }
        return task
    }

    public func task(for resource: String) -> CleanupTask? {
        let resources = [resource, Self.canonicalResource(resource)]
        return pending.first { task in
            task.items.contains { item in
                item.resources.contains { held in resources.contains { Self.overlaps(held, $0) } }
            }
        }
    }

    public func status(for resource: String) -> StatusWords? {
        guard let task = task(for: resource) else { return nil }
        let resources = [resource, Self.canonicalResource(resource)]
        let matching = task.items.filter { item in
            item.resources.contains { held in resources.contains { Self.overlaps(held, $0) } }
        }
        if matching.contains(where: { $0.state == .running }) {
            return StatusWords("Cleaning…", .blue, symbol: "arrow.triangle.2.circlepath")
        }
        return StatusWords("Queued", .blue, symbol: "clock")
    }
    public static let lockedHelp = "This item already has a cleanup task. Open its progress to review or stop it."
    public func open(_ resource: String) { selectedTask = task(for: resource) }
    public func place(of task: CleanupTask) -> Int? { pending.firstIndex { $0.id == task.id }.map { $0 + 1 } }

    public func cancel(_ task: CleanupTask) {
        guard task.state == .queued || task.state == .waiting else { return }
        task.state = .cancelled
        for index in task.items.indices { task.items[index].state = .stopped }
        jobs[task.id] = nil
        resumeIfEmpty()
    }
    public func stop(_ task: CleanupTask) {
        guard task.state == .running else { return }
        task.stopRequested = true
    }
    public func dismissToast(_ id: UUID) { toasts.removeAll { $0.id == id } }

    /// Auto mode resumes exactly when the pending queue empties; it never takes a lock while waiting.
    public func waitUntilEmpty() async {
        guard hasPending else { return }
        await withCheckedContinuation { emptyWaiters.append($0) }
    }

    func prepareToQuit() {
        for task in pending {
            if task.state == .running { stop(task) } else { cancel(task) }
        }
    }
    public var quitMessage: String {
        "Bonsai is cleaning. Quit after the current item? \(queuedCount) queued tasks won't run."
    }

    nonisolated static func canonicalResource(_ value: String) -> String {
        guard value.hasPrefix("/") else { return value }
        return CanonicalPath.resolve(value)
    }
    nonisolated static func overlaps(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || (lhs.hasPrefix("/") && rhs.hasPrefix("/")
            && (lhs.hasPrefix(rhs + "/") || rhs.hasPrefix(lhs + "/")))
    }
}
