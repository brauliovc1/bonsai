import Foundation

/// The append-only cleanup log, `<settingsDir>/removals.jsonl`: one JSON object per line.
///
/// Appending is one `write` of one line followed by `fsync`. A crash mid-write can leave a partial last
/// line; reading skips it, and the next append starts on a fresh line. The only rewrite is marking an
/// entry restored, done atomically and keeping every other line byte for byte.
public struct RemovalLog: Sendable {
    public static let fileName = "removals.jsonl"

    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public init(environment: CleanEnvironment) {
        self.init(directory: environment.settingsDirectory)
    }

    public var fileURL: URL { directory.appending(path: Self.fileName) }

    public struct LogError: Error, Sendable, CustomStringConvertible {
        public var description: String
    }

    /// The entries in file order. Lines that don't decode (a partial last line) are skipped.
    public func entries() throws -> [RemovalLogEntry] {
        try lines().compactMap(Self.decode)
    }

    public func entry(id: UUID) throws -> RemovalLogEntry? {
        try entries().last { $0.id == id }
    }

    /// Appends one entry.
    public func append(_ entry: RemovalLogEntry) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var line = try Self.encode(entry)
        if try !endsWithNewline() { line.insert(UInt8(ascii: "\n"), at: line.startIndex) }

        let descriptor = open(fileURL.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { throw LogError(description: "cannot open \(fileURL.path): \(Self.errnoText())") }
        defer { close(descriptor) }
        let written = line.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        guard written == line.count else {
            throw LogError(description: "cannot write \(fileURL.path): \(written < 0 ? Self.errnoText() : "short write")")
        }
        guard fsync(descriptor) == 0 else { throw LogError(description: "cannot sync \(fileURL.path): \(Self.errnoText())") }
    }

    /// Sets `restoredAt` on one entry and rewrites the file atomically.
    public func markRestored(id: UUID, at date: Date) throws {
        var found = false
        var output = Data()
        for line in try lines() {
            if var entry = Self.decode(line), entry.id == id {
                entry.restoredAt = date
                output.append(try Self.encode(entry))
                found = true
            } else {
                output.append(line)
                output.append(UInt8(ascii: "\n"))
            }
        }
        guard found else { throw LogError(description: "no log entry \(id.uuidString)") }
        try output.write(to: fileURL, options: .atomic)
    }

    // MARK: - Lines

    private func lines() throws -> [Data] {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
        return data.split(separator: UInt8(ascii: "\n")).filter { !$0.allSatisfy { $0 == UInt8(ascii: " ") } }
    }

    private func endsWithNewline() throws -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return true }
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        guard size > 0 else { return true }
        try handle.seek(toOffset: size - 1)
        return try handle.read(upToCount: 1) == Data([UInt8(ascii: "\n")])
    }

    /// One compact JSON line, newline included.
    static func encode(_ entry: RemovalLogEntry) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(entry)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    static func decode(_ line: Data) -> RemovalLogEntry? {
        try? CleanJSON.decoder().decode(RemovalLogEntry.self, from: line)
    }

    private static func errnoText() -> String {
        String(cString: strerror(errno))
    }
}
