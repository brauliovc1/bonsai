import CleanCore
import Foundation

extension AppModel {
    /// "Test mode: scanning only <folder> (CLEAN_CLAUDE_SCAN_ROOTS)" while that variable is set, so a demo
    /// world's repos aren't taken for the Mac's own; nil otherwise. Several folders are listed with commas.
    public var testModeText: String? {
        guard let roots = environment.scanRootsOverride, !roots.isEmpty else { return nil }
        let folders = roots.map { TildePath.abbreviate($0.path, home: environment.homeDirectory) }
        return "Test mode: scanning only \(folders.joined(separator: ", ")) (CLEAN_CLAUDE_SCAN_ROOTS)"
    }
}
