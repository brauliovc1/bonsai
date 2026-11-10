import Foundation

/// Reads and writes `<settingsDir>/settings.json`. The app and the CLI both change it, so every
/// read-modify-write (`update`) holds an exclusive `flock` on `settings.lock` (PLAN §3): a change made in
/// between can't be put back by an older copy.
public struct SettingsStore: Sendable {
    public static let fileName = "settings.json"
    public static let lockFileName = "settings.lock"

    public var directory: URL
    /// How long `update` and `loadLocked` wait for another process's lock.
    public var lockTimeout: Duration = .seconds(5)

    public init(directory: URL) {
        self.directory = directory
    }

    public init(environment: CleanEnvironment) {
        self.init(directory: environment.settingsDirectory)
    }

    public var fileURL: URL { directory.appending(path: Self.fileName) }
    public var lockURL: URL { directory.appending(path: Self.lockFileName) }

    public struct LoadError: Error, Sendable, CustomStringConvertible {
        public var path: String
        public var message: String
        public var description: String { "cannot read \(path): \(message)" }
    }

    /// The saved settings; a missing file gives the defaults. A file that exists but cannot be read or
    /// decoded, or holds values outside their range (`Settings.problems`), throws, so a broken file is never
    /// silently replaced by defaults.
    public func load() throws -> Settings {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return Settings()
        } catch {
            throw LoadError(path: fileURL.path, message: error.localizedDescription)
        }
        let settings: Settings
        do {
            settings = try CleanJSON.decoder().decode(Settings.self, from: data)
        } catch {
            throw LoadError(path: fileURL.path, message: "\(error)")
        }
        guard settings.problems.isEmpty else {
            throw LoadError(path: fileURL.path, message: settings.problems.joined(separator: "; "))
        }
        return settings
    }

    /// Reads the file, changes it and saves it, holding `settings.lock` throughout. A file that can't be read
    /// is never overwritten (the load throws first). Returns what was saved.
    @discardableResult
    public func update(_ change: (inout Settings) throws -> Void) throws -> Settings {
        let lock = try FileLock.lock(lockURL, timeout: lockTimeout)
        defer { lock.release() }
        var settings = try load()
        try change(&settings)
        try save(settings)
        return settings
    }

    /// `load()` while holding `settings.lock`, so a write in progress elsewhere finishes first. Without a
    /// settings folder there is nothing to wait for (and nothing is created).
    public func loadLocked() throws -> Settings {
        guard FileManager.default.fileExists(atPath: directory.path) else { return try load() }
        let lock = try FileLock.lock(lockURL, timeout: lockTimeout)
        defer { lock.release() }
        return try load()
    }

    /// Writes the settings atomically (pretty, sorted keys, ISO 8601 dates), creating the folder if needed.
    /// Settings with `problems` are refused.
    public func save(_ settings: Settings) throws {
        guard settings.problems.isEmpty else {
            throw LoadError(path: fileURL.path, message: "not saved: " + settings.problems.joined(separator: "; "))
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var data = try CleanJSON.encoder().encode(settings)
        data.append(UInt8(ascii: "\n"))
        try data.write(to: fileURL, options: .atomic)
    }
}
