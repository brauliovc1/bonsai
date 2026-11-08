import CleanCore
import Foundation
import Observation

/// The General tab of Settings: scan roots, the idle threshold and the low-space warning. Every change is
/// read from `settings.json`, changed, and saved again through `SettingsStore`, so keys other screens or
/// the CLI own are kept, and a file that can't be read is never overwritten. Changing the roots or the
/// threshold scans again.
@MainActor
@Observable
public final class SettingsModel {
    public static let idleThresholdRange = Settings.idleThresholdRange
    public static let lowSpaceRange = 1...1000
    public static let emptyRootsText = "No folders added: ~/Documents/GitHub is scanned."

    public let app: AppModel
    public private(set) var scanRoots: [String] = []
    /// Roots in the file that are skipped (the rule: only a folder inside home or on an external volume).
    public private(set) var refusedRoots: [ScanRootRule.Refusal] = []
    public private(set) var idleThresholdDays = Settings().idleThresholdDays
    public private(set) var lowSpaceWarningGB = Settings().lowSpaceWarningGB
    /// Why settings couldn't be read or saved; the controls then change nothing.
    public private(set) var error: String?

    public init(app: AppModel) {
        self.app = app
        load()
    }

    /// The roots the last scan used (the list, or the default folder when the list is empty).
    public var scanningText: String {
        app.roots.isEmpty ? "Nothing to scan yet." : "Scanning " + app.roots.map(\.path).joined(separator: ", ")
    }

    /// `CLEAN_CLAUDE_SCAN_ROOTS` replaces the list for this run (development); the list is still saved.
    public var overrideText: String? {
        app.environment.scanRootsOverride.map {
            "This run scans " + $0.map(\.path).joined(separator: ", ") + " (CLEAN_CLAUDE_SCAN_ROOTS); the list below is kept for other runs."
        }
    }

    /// Reads `settings.json` into the screen.
    public func load() {
        do {
            apply(try SettingsStore(environment: app.environment).load())
            error = nil
        } catch {
            self.error = "\(error)"
        }
    }

    // MARK: - Scan roots

    /// Adds a folder, saved with its symlinks resolved, then scans again. Folders only, and only what
    /// `ScanRootRule` accepts (inside home or on an external volume); one already in the list is ignored.
    /// Returns false when it was not added.
    @discardableResult
    public func addRoot(_ url: URL) async -> Bool {
        let folder = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            error = "\(folder.path) is not a folder."
            return false
        }
        let home = app.environment.homeDirectory
        let rule = ScanRootRule(home: home)
        let canonical: URL
        switch rule.accept(folder) {
        case .success(let accepted): canonical = accepted
        case .failure(let refusal):
            error = "\(refusal.path) can't be a scan root: \(refusal.reason)."
            return false
        }
        guard !scanRoots.contains(where: { rule.canonical(CleanEnvironment.expand($0, home: home))?.path == canonical.path })
        else { return false }
        guard update({ $0.scanRoots.append(canonical.path) }) else { return false }
        await app.refresh()
        return true
    }

    /// Why a root in the list is skipped by scans, or nil when it is used.
    public func skippedReason(of root: String) -> String? {
        let path = CleanEnvironment.expand(root, home: app.environment.homeDirectory).path
        return refusedRoots.first { $0.path == path }?.reason
    }

    /// Removes a folder from the list (the folder itself is untouched), then scans again.
    public func removeRoot(_ path: String) async {
        guard scanRoots.contains(path), update({ $0.scanRoots.removeAll { $0 == path } }) else { return }
        await app.refresh()
    }

    // MARK: - Thresholds

    /// Sets the idle threshold (clamped to 7...365 days), then scans again: statuses use it.
    public func setIdleThreshold(_ days: Int) async {
        let clamped = min(max(days, Self.idleThresholdRange.lowerBound), Self.idleThresholdRange.upperBound)
        guard clamped != idleThresholdDays, update({ $0.idleThresholdDays = clamped }) else { return }
        await app.refresh()
    }

    /// Sets the low-space warning (clamped to 1...1000 GB). Nothing to scan again.
    public func setLowSpaceWarning(_ gigabytes: Int) {
        let clamped = min(max(gigabytes, Self.lowSpaceRange.lowerBound), Self.lowSpaceRange.upperBound)
        guard clamped != lowSpaceWarningGB else { return }
        update { $0.lowSpaceWarningGB = clamped }
    }

    // MARK: - Saving

    @discardableResult
    private func update(_ change: (inout Settings) -> Void) -> Bool {
        let store = SettingsStore(environment: app.environment)
        do {
            let settings = try store.update(change)
            apply(settings)
            app.reloadSettings()
            error = nil
            return true
        } catch {
            self.error = "\(error)"
            return false
        }
    }

    private func apply(_ settings: Settings) {
        scanRoots = settings.scanRoots
        refusedRoots = settings.refusedScanRoots(home: app.environment.homeDirectory)
        idleThresholdDays = settings.idleThresholdDays
        lowSpaceWarningGB = settings.lowSpaceWarningGB
    }
}
