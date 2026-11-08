import CleanCore
import Foundation

/// Changes some keys of `settings.json` the way `SettingsModel` does: read the file, change only the
/// caller's keys, save through `SettingsStore`, then `app.reloadSettings()`, all holding `settings.lock`.
/// A file that can't be read is never overwritten (the load throws first), and settings with problems (a
/// threshold outside 7...365) are refused by the store.
@MainActor
enum SettingsEditor {
    @discardableResult
    static func update(_ app: AppModel, _ change: (inout Settings) -> Void) throws -> Settings {
        let saved = try SettingsStore(environment: app.environment).update(change)
        app.reloadSettings()
        return saved
    }

    /// The saved settings, read now under `settings.lock` (not the copy the last scan loaded).
    static func current(_ app: AppModel) throws -> Settings {
        try SettingsStore(environment: app.environment).loadLocked()
    }
}
