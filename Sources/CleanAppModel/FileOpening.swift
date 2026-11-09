import Foundation
import UniformTypeIdentifiers

/// Whether and how "Open" opens a file from a worktree's file list, so that it never runs anything (P12b review): an
/// allowlist, not a list of what runs. Images and PDFs open in their default app; text and source code open as text
/// in TextEdit (a script's default app can be Terminal, an HTML file's a browser); everything else (archives such as
/// `.jar`, Java classes, Terminal sessions, executable files, apps and other packages, symlinks) gets no Open: Show in
/// Finder and Copy path only.
public enum FileOpening: Equatable, Sendable {
    /// Its default app: an image, a PDF, or a plain folder (Finder).
    case defaultApp
    /// As text, in TextEdit: text or source code.
    case asText
    /// No Open; only shown in Finder.
    case finderOnly

    /// Looks at the item itself (symlinks not followed).
    public static func way(for url: URL) -> FileOpening {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isExecutableKey,
                                         .isRegularFileKey, .contentTypeKey]
        guard let values = try? url.resourceValues(forKeys: keys), values.isSymbolicLink != true else { return .finderOnly }
        if values.isDirectory == true { return values.isPackage == true ? .finderOnly : .defaultApp }
        guard values.isRegularFile == true, values.isExecutable != true else { return .finderOnly }
        let type = values.contentType ?? UTType(filenameExtension: url.pathExtension) ?? .data
        if type.conforms(to: .image) || type.conforms(to: .pdf) { return .defaultApp }
        if type.conforms(to: .text) || type.conforms(to: .sourceCode) { return .asText }
        return .finderOnly
    }
}
