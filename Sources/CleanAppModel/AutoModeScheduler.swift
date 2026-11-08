import CleanCore
import Foundation

/// Asks auto mode to check every hour (NSBackgroundActivityScheduler), at launch, and a few minutes after the
/// Mac wakes. The checks decide (`AutoSchedule.shouldRun`: at least 24 h since the last run); this only asks.
/// Nothing runs while the app isn't running.
@MainActor
public final class AutoModeScheduler {
    public static let identifier = "io.github.brauliovc1.bonsai.auto"

    let model: AutoModeModel
    /// How long after a wake the check waits (tests shorten it).
    var wakeDelay: Duration = AutoSchedule.wakeDelay
    private var activity: NSBackgroundActivityScheduler?
    private var wakeObserver: NSObjectProtocol?
    private var wakeCenter: NotificationCenter?
    private var wakeCheck: Task<Void, Never>?

    public init(model: AutoModeModel) {
        self.model = model
    }

    /// Starts the hourly activity (repeats, 10 minutes tolerance, utility), observes `wakeName` on
    /// `wakeCenter` (the app passes NSWorkspace's didWake), and checks once now (the launch check).
    /// `hourly: false` leaves the background activity out (tests).
    public func start(wakeCenter: NotificationCenter, wakeName: Notification.Name, hourly: Bool = true) {
        guard wakeObserver == nil else { return }
        if hourly { scheduleHourly() }
        self.wakeCenter = wakeCenter
        wakeObserver = wakeCenter.addObserver(forName: wakeName, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.didWake() }
        }
        Task { await model.checkSchedule() }
    }

    public func stop() {
        activity?.invalidate()
        activity = nil
        wakeCheck?.cancel()
        wakeCheck = nil
        if let wakeObserver { wakeCenter?.removeObserver(wakeObserver) }
        wakeObserver = nil
        wakeCenter = nil
    }

    /// Right after a wake the Mac can be too busy for timed work: the check waits `wakeDelay` (on a clock that
    /// doesn't count sleep). Another wake meanwhile starts the wait again.
    private func didWake() {
        wakeCheck?.cancel()
        let delay = wakeDelay
        wakeCheck = Task { [weak model] in
            do {
                try await Task.sleep(for: delay, tolerance: nil, clock: SuspendingClock())
            } catch {
                return
            }
            await model?.checkSchedule()
        }
    }

    private func scheduleHourly() {
        let activity = NSBackgroundActivityScheduler(identifier: Self.identifier)
        activity.repeats = true
        activity.interval = AutoSchedule.checkInterval
        activity.tolerance = AutoSchedule.checkTolerance
        activity.qualityOfService = .utility
        activity.schedule { [weak model] completion in
            let done = Completion(completion)
            Task { @MainActor in
                await model?.checkSchedule()
                done.call()
            }
        }
        self.activity = activity
    }
}

/// The activity's completion handler, called once from the main actor when the check is done.
private struct Completion: @unchecked Sendable {
    let handler: NSBackgroundActivityScheduler.CompletionHandler

    init(_ handler: @escaping NSBackgroundActivityScheduler.CompletionHandler) {
        self.handler = handler
    }

    func call() {
        handler(.finished)
    }
}
