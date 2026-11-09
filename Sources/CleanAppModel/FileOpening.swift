import Foundation

/// How "Open" opens a file from a worktree's file list without running anything: Finder runs an app and Terminal
/// runs a script it is asked to open, so those open as text (or are shown in Finder) instead of in their default app.
public enum FileOpening: Equatable, Sendable {
    /// Its default app (a document, an image, a plain folder in Finder).
    case defaultApp
    /// As text, in TextEdit: a script or an executable file.
    case asText
    /// Only shown in Finder: an app or another package, or something that can't be looked at.
    case finderOnly

    /// Extensions that open in Terminal or Script Editor and run there.
    static let runnableExtensions: Set<String> = [
        "command", "tool", "terminal", "sh", "zsh", "bash", "csh", "ksh", "fish", "py", "rb", "pl", "php", "js",
        "workflow", "scpt", "applescript", "action",
    ]

    /// Looks at the item itself (symlinks not followed).
    public static func way(for url: URL) -> FileOpening {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey,
                                                            .isExecutableKey, .isRegularFileKey])
        else { return .finderOnly }
        if values.isSymbolicLink == true { return .finderOnly }
        if values.isDirectory == true { return values.isPackage == true ? .finderOnly : .defaultApp }
        guard values.isRegularFile == true else { return .finderOnly }
        if values.isExecutable == true || runnableExtensions.contains(url.pathExtension.lowercased()) { return .asText }
        return .defaultApp
    }
}
