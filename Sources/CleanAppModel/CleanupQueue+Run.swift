import Foundation

extension CleanupQueue {
    func drain() async {
        let app = app // Keep the owner alive until this worker finishes, including lock backoff.
        while let task = current, !app.isQuitting {
            guard let job = jobs[task.id] else { break }
            let ran: Void? = await app.cleaningUp {
                task.state = .running
                task.waitingReason = nil
                for index in job.work.indices {
                    guard !task.stopRequested, !app.isQuitting else {
                        for remaining in index..<task.items.count { task.items[remaining].state = .stopped }
                        break
                    }
                    task.items[index].state = .running
                    let result = await job.work[index].run()
                    task.items[index].result = result
                    switch result.state {
                    case .cleaned: task.items[index].state = .done
                    case .refused: task.items[index].state = .refused
                    case .failed: task.items[index].state = .failed
                    }
                }
                // Keep the path reservations through size invalidation and the per-task refresh.
                if !app.isQuitting { await job.finish(task) }
                else { app.reloadLog() }
            }
            if ran == nil {
                if app.isQuitting { break }
                if let error = app.cleanupLockError {
                    for index in task.items.indices {
                        task.items[index].state = .failed
                        task.items[index].result = CleanupItemResult(.failed, detail: error)
                    }
                    task.state = .failed
                } else {
                    task.state = .waiting
                    task.waitingReason = app.busySentence
                    await sleep(.milliseconds(250))
                    continue
                }
            } else {
                task.state = task.items.contains { $0.state == .stopped } ? .stopped : (task.hasProblems ? .failed : .done)
            }
            jobs[task.id] = nil
            completed(task)
            resumeIfEmpty()
            if !windowIsVisible { await notify(task) }
            // Leave a scheduling point between tasks; the CLI or auto mode may acquire the lock here.
            await Task.yield()
        }
        runner = nil
        resumeIfEmpty()
    }

    func resumeIfEmpty() {
        guard !hasPending else { return }
        let waiters = emptyWaiters
        emptyWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    private func completed(_ task: CleanupTask) {
        let toast = CleanupToast(task: task)
        toasts.append(toast)
        if !toast.needsReview {
            Task { [weak self] in
                guard let self else { return }
                await toastSleep()
                dismissToast(toast.id)
            }
        }
    }
}
