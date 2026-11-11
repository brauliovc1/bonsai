import Foundation

public struct LocalSnapshot: Sendable, Codable, Hashable, Identifiable {
    public let id: String
    public let date: Date
}

public struct LocalSnapshots: Sendable, Codable, Hashable {
    public let snapshots: [LocalSnapshot]
    public let purgeableBytes: Int64?
    public let warnings: [String]

    public static func purgeable(important: Int64?, available: Int64?) -> Int64? {
        guard let important, let available else { return nil }
        return max(0, important - available)
    }

    public static func parse(_ text: String, timeZone: TimeZone = .current) -> [LocalSnapshot] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.isLenient = false
        let prefix = "com.apple.TimeMachine."
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let name = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.hasPrefix(prefix), name.hasSuffix(".local") else { return nil }
            let stamp = String(name.dropFirst(prefix.count).dropLast(".local".count))
            guard let date = formatter.date(from: stamp), formatter.string(from: date) == stamp else { return nil }
            return LocalSnapshot(id: name, date: date)
        }.sorted { $0.date > $1.date }
    }

    public static func read(home: URL, runner: CommandRunner = .live) async -> Self {
        let values = try? URL(fileURLWithPath: home.path).resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let purgeable = purgeable(important: values?.volumeAvailableCapacityForImportantUsage,
                                  available: values?.volumeAvailableCapacity.map(Int64.init))
        do {
            let result = try await runner.run(URL(fileURLWithPath: "/usr/bin/tmutil"),
                                              ["listlocalsnapshots", "/"], timeout: .seconds(60))
            guard result.succeeded else { return Self(snapshots: [], purgeableBytes: purgeable, warnings: ["Could not read local snapshots."]) }
            return Self(snapshots: parse(result.stdoutString), purgeableBytes: purgeable, warnings: [])
        } catch { return Self(snapshots: [], purgeableBytes: purgeable, warnings: ["Could not read local snapshots: \(error.localizedDescription)"]) }
    }
}
