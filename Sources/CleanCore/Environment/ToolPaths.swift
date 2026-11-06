import Foundation

/// Absolute paths of the external tools clean-claude runs. A nil tool is missing: callers show that as a
/// clear state, never crash.
public struct ToolPaths: Sendable, Equatable {
    public var git: URL?
    public var du: URL?
    public var lsof: URL?
    public var xcrun: URL?
    public var defaults: URL?
    public var docker: URL?
    /// `xcode-select -p` succeeded, so the `/usr/bin` developer shims are safe to run.
    public var developerToolsInstalled: Bool

    public init(
        git: URL? = nil,
        du: URL? = nil,
        lsof: URL? = nil,
        xcrun: URL? = nil,
        defaults: URL? = nil,
        docker: URL? = nil,
        developerToolsInstalled: Bool = false
    ) {
        self.git = git
        self.du = du
        self.lsof = lsof
        self.xcrun = xcrun
        self.defaults = defaults
        self.docker = docker
        self.developerToolsInstalled = developerToolsInstalled
    }

    /// Picks the first executable candidate for each tool. Candidates that need the developer tools are
    /// skipped when `developerToolsInstalled` returns false.
    public static func resolve(
        candidates: ToolCandidates = .standard,
        isExecutable: (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) },
        developerToolsInstalled: () -> Bool = ToolPaths.xcodeSelectSucceeds
    ) -> ToolPaths {
        let hasDeveloperTools = developerToolsInstalled()
        func first(_ urls: [URL]) -> URL? {
            urls.first { url in
                if !hasDeveloperTools && candidates.requiringDeveloperTools.contains(url) { return false }
                return isExecutable(url)
            }
        }
        return ToolPaths(
            git: first(candidates.git),
            du: first(candidates.du),
            lsof: first(candidates.lsof),
            xcrun: first(candidates.xcrun),
            defaults: first(candidates.defaults),
            docker: first(candidates.docker),
            developerToolsInstalled: hasDeveloperTools
        )
    }

    /// Runs `/usr/bin/xcode-select -p`: true when it exits 0 and the folder it prints exists.
    /// `xcode-select` itself never shows the Command Line Tools installer.
    public static func xcodeSelectSucceeds() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        // The output is a single short line, far below the pipe buffer, so reading after exit is safe.
        process.waitUntilExit()
        let data = (try? output.fileHandleForReading.readToEnd()) ?? Data()
        guard process.terminationStatus == 0 else { return false }
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return !path.isEmpty && FileManager.default.fileExists(atPath: path)
    }
}
