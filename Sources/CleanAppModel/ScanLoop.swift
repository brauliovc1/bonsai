/// One scan at a time for a screen's model: a refresh asked for while one runs doesn't start a second, it
/// asks for exactly one more run after the running one, however often it is asked (like `AppModel.refresh`).
@MainActor
final class ScanLoop {
    private var task: Task<Void, Never>?
    private var again = false

    var isRunning: Bool { task != nil }

    /// Runs `body` now, or once more after the running one; returns when that run is done.
    func run(_ body: @escaping @MainActor () async -> Void) async {
        if let task {
            again = true
            await task.value
            return
        }
        let task = Task {
            repeat {
                again = false
                await body()
            } while again
            self.task = nil
        }
        self.task = task
        await task.value
    }
}
