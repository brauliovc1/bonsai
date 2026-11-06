import Foundation

/// Reads and writes `<settingsDir>/settings.json`.
public struct SettingsStore: Sendable {
    public static let fileName = "settings.json"

    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public init(environment: CleanEnvironment) {
        self.init(directory: environment.settingsDirectory)
    }

    public var fileURL: URL { directory.appending(path: Self.fileName) }

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
