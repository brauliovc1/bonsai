import Foundation

/// How long a test waits for one step (a helper process to start or end, a lock, a scan, a held call, a CLI run)
/// before it says that step ran out of time. Minutes on purpose: GitHub's macOS runner is several times slower than
/// a Mac and single tests ran 5–8 minutes there (run 42759884210), and on efficiency cores alone
/// (`taskpolicy -c background`) one step can take minutes. A step that works takes a fraction of this, so only a
/// broken one waits it out.
public enum TestWait {
    public static let limit: Duration = .seconds(600)

    /// `limit` in seconds.
    public static var seconds: Double { Double(limit.components.seconds) }

    /// `limit` from now, for semaphores and groups.
    public static var deadline: DispatchTime { .now() + seconds }
}
