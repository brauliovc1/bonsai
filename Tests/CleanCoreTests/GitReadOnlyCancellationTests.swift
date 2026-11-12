import CleanCore
import CleanTestSupport
import Darwin
import Foundation
import Testing

@Suite("Git read-only cancellation", .serialized)
struct GitReadOnlyCancellationTests {
    @Test(arguments: [false, true])
    func cancellingAStartedCommandThrowsCancellation(readData: Bool) async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let repo = try await fixture.makeRepo("cancelled-read")
        let executable = fixture.url.appending(path: "held-git")
        let ready = fixture.url.appending(path: "ready")
        let hold = fixture.url.appending(path: "hold")
        try #require(mkfifo(ready.path, 0o600) == 0 && mkfifo(hold.path, 0o600) == 0)
        let descriptor = open(ready.path, O_RDWR | O_NONBLOCK | O_CLOEXEC)
        try #require(descriptor >= 0)
        defer { close(descriptor) }
        // Signal only after ProcessRunner has started this process, then wait for cancellation.
        // A shell builtin blocks on the second FIFO; there is no child process or timer to race.
        try Data("""
        #!/bin/sh
        folder=${0%/*}
        printf . > "$folder/ready"
        read answer < "$folder/hold"
        """.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let git = try GitReadOnly(repository: repo, executable: executable, timeout: TestWait.limit)
        let task = Task {
            if readData { _ = try await git.data(["rev-parse", "--verify", "HEAD"]) }
            else { _ = try await git.result(["rev-parse", "--verify", "HEAD"]) }
        }
        let started = await Self.readByte(descriptor)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(started, "Cancellation must happen after the executable signals that it started.")
    }

    /// Wait on an OS event on a dedicated helper thread, without occupying a shared executor.
    private static func readByte(_ descriptor: Int32) async -> Bool {
        let threads = TestThreads()
        return await withCheckedContinuation { continuation in
            threads.start {
                let clock = ContinuousClock(), deadline = ContinuousClock.now.advanced(by: TestWait.limit)
                while clock.now < deadline {
                    var event = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
                    let left = clock.now.duration(to: deadline).components
                    let milliseconds = Int32(left.seconds * 1_000 + left.attoseconds / 1_000_000_000_000_000 + 1)
                    let ready = poll(&event, 1, milliseconds)
                    if ready < 0 && errno == EINTR { continue }
                    guard ready > 0 else { continuation.resume(returning: false); return }
                    var byte: UInt8 = 0
                    continuation.resume(returning: read(descriptor, &byte, 1) == 1)
                    return
                }
                continuation.resume(returning: false)
            }
        }
    }
}
