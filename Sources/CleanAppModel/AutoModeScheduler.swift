import CleanCore
import Foundation

/// Asks auto mode to check once a day (NSBackgroundActivityScheduler), at launch, and when the Mac wakes.
/// The checks decide (`AutoSchedule.shouldRun`); this only asks. Nothing runs while the app isn't running.
@MainActor
public final class AutoModeScheduler {
    public static let identifier = "io.github.brauliovc1.bonsai.auto"

    let model: AutoModeModel
    private var activity: NSBackgroundActivityScheduler?
    private var wakeObserver: NSObjectProtocol?
    private var wakeCenter: NotificationCenter?

    public init(model: AutoModeModel) {
        self.model = model
    }

    /// Starts the daily activity (repeats every 24 h, 1 h tolerance, utility), observes `wakeName` on
    /// `wakeCenter` (the app passes NSWorkspace's didWake), and checks once now (the launch check).
    /// `daily: false` leaves the background activity out (tests).
    public func start(wakeCenter: NotificationCenter, wakeName: Notification.Name, daily: Bool = true) {
        guard wakeObserver == nil else { return }
        if daily { scheduleDaily() }
        self.wakeCenter = wakeCenter
        wakeObserver = wakeCenter.addObserver(forName: wakeName, object: nil, queue: .main) { [weak model] _ in
            Task { @MainActor in await model?.checkSchedule() }
        }
        Task { await model.checkSchedule() }
    }

    public func stop() {
        activity?.invalidate()
        activity = nil
        if let wakeObserver { wakeCenter?.removeObserver(wakeObserver) }
        wakeObserver = nil
        wakeCenter = nil
    }

    private func scheduleDaily() {
        let activity = NSBackgroundActivityScheduler(identifier: Self.identifier)
        activity.repeats = true
        activity.interval = AutoSchedule.interval
        activity.tolerance = AutoSchedule.tolerance
        activity.qualityOfService = .utility
        activity.schedule { [weak model] completion in
            let done = Completion(completion)
            Task { @MainActor in
                await model?.checkSchedule(early: AutoSchedule.tolerance)
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
