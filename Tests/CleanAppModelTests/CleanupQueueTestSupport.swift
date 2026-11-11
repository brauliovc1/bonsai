@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@MainActor
final class QueueGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false
    private(set) var entered = false
    func wait() async {
        entered = true
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
func queueWork(_ resource: String, bytes: Int64? = nil,
               run: @escaping @MainActor () async -> CleanupItemResult = { CleanupItemResult(.cleaned) }) -> CleanupWork {
    CleanupWork(CleanupItem(name: resource, resources: [resource], estimatedBytes: bytes), run: run)
}

/// A second process owns cleanup.lock until this test closes its input. It never expires on its own.
@MainActor
final class QueueLockHolder {
    let process = Process()
    let input = Pipe()

    static func take(_ app: AppModel) async throws -> QueueLockHolder {
        let folder = app.environment.settingsDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "cleanup.lock")
        let holder = QueueLockHolder()
        holder.process.executableURL = URL(fileURLWithPath: "/usr/bin/lockf")
        holder.process.arguments = ["-k", file.path, "/bin/sh", "-c", "read line"]
        holder.process.standardInput = holder.input
        holder.process.standardOutput = FileHandle.nullDevice
        holder.process.standardError = FileHandle.nullDevice
        try holder.process.run()
        let acquired = await eventually {
            do {
                guard let lock = try FileLock.tryLock(file, createsFolder: false) else { return true }
                lock.release()
                return false
            } catch { return false }
        }
        guard acquired else { holder.close(); throw SetupError(description: "lock holder did not acquire cleanup.lock within \(TestWait.limit)") }
        return holder
    }
    func close() { try? input.fileHandleForWriting.close() }
    func release() async {
        close()
        #expect(await eventually { !self.process.isRunning })
    }
    deinit { try? input.fileHandleForWriting.close() }
}
