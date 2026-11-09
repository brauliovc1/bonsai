import CleanCore
import Foundation

extension AppModel {
    /// "Test mode: scanning only <folder> (CLEAN_CLAUDE_SCAN_ROOTS)" while that variable is set, so a demo
    /// world's repos aren't taken for the Mac's own; nil otherwise. Several folders are listed with commas.
    public var testModeText: String? {
        testModeFolders.map { "Test mode: scanning only \($0) (CLEAN_CLAUDE_SCAN_ROOTS)" }
    }

    /// The folders of `testModeText` alone ("~/demo, /tmp/w"), for views that cut the folder, not the sentence.
    public var testModeFolders: String? {
        guard let roots = environment.scanRootsOverride, !roots.isEmpty else { return nil }
        return roots.map { TildePath.abbreviate($0.path, home: environment.homeDirectory) }.joined(separator: ", ")
    }
}
