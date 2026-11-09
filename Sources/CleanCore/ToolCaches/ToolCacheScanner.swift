import Foundation

/// Looks at every catalog entry (PLAN §4.6): which of its paths exist, the path rules, the Cursor rules, the
/// owners, and the size of what would go (`du`, at most four at a time). Read-only.
public struct ToolCacheScanner: Sendable {
    public var homeDirectory: URL
    /// For size estimates; nil = no sizes.
    public var du: URL?
    public var now: @Sendable () -> Date
    public var processes: ProcessSource
    var catalog = ToolCacheCatalog.entries

    public init(homeDirectory: URL, du: URL?, processes: ProcessSource, now: @escaping @Sendable () -> Date = { Date() }) {
        self.homeDirectory = homeDirectory
        self.du = du
        self.processes = processes
        self.now = now
    }

    public init(environment: CleanEnvironment, processes: ProcessSource = .live()) {
        self.init(homeDirectory: environment.homeDirectory, du: environment.tools.du, processes: processes, now: environment.now)
    }

    public func scan() async -> ToolCacheReport {
        // The process list comes first, so the scanner's own du is never taken for a program using a cache.
        let list = await processes.capture()
        let date = now()
        let inspections = catalog.compactMap {
            ToolCacheInspection.inspect($0, home: homeDirectory, processes: list, now: date)
        }
        var warnings: [String] = []
        if let failure = list.failure {
            warnings.append("the process list couldn't be read (\(failure)), so nothing can be cleaned")
        }

        var sizes: [String: Int64] = [:]
        var failed = Set<String>()
        if let du {
            let paths = Array(Set(inspections.flatMap(\.measuredPaths))).sorted()
            let measured = await DirectorySizer(du: du).allocatedSizes(ofItems: paths.map { URL(fileURLWithPath: $0) })
            sizes = measured.sizes
            failed = Set(measured.issues.compactMap(\.path))
            warnings += measured.issues.map(\.description)
        }
        let findings = inspections.map { inspection in
            let paths = inspection.measuredPaths
            let unknown = du == nil || paths.isEmpty || paths.contains(where: failed.contains)
            return ToolCacheFinding(
                inspection: inspection,
                bytes: unknown ? nil : paths.compactMap { sizes[$0] }.reduce(0, +),
                removalBytes: sizes.filter { inspection.removals.contains($0.key) }
            )
        }
        return ToolCacheReport(
            findings: findings,
            cursorRunning: list.isCursorRunning,
            processListFailure: list.failure,
            warnings: warnings
        )
    }
}
