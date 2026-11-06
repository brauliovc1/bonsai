/// Folder and file names that tools regenerate (PLAN §4.2). One list, used to ignore harmless ignored
/// files in the removal checks (§4.1), to skip folders in the idle clock (§4.3), and as the light-clean
/// allowlist (P4).
public enum RegenerableNames {
    /// Dependency and build-output folders.
    public static let folders: Set<String> = [
        "node_modules", ".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache", ".angular", "coverage",
        "dist", "dist-test", "build", ".build", ".dart_tool", "Pods", ".gradle", "__pycache__", ".pytest_cache",
        ".mypy_cache", ".ruff_cache", ".venv", "venv", "target", "DerivedData", ".expo",
    ]

    /// Exact file names that are harmless when ignored (§4.1 only, never light-cleaned).
    public static let fileNames: Set<String> = [
        ".DS_Store", "next-env.d.ts", ".eslintcache", ".flutter-plugins", ".flutter-plugins-dependencies",
        ".packages",
    ]

    /// File extensions (`*.log` -> `log`) that are harmless when ignored (§4.1 only).
    public static let fileExtensions: Set<String> = ["log", "tsbuildinfo", "pyc"]

    public static func isRegenerableFolder(_ name: String) -> Bool {
        folders.contains(name)
    }

    public static func isHarmlessFile(_ name: String) -> Bool {
        if fileNames.contains(name) { return true }
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
        return fileExtensions.contains(String(name[name.index(after: dot)...]))
    }

    /// Whether one entry of `git ls-files --others --ignored --exclude-standard --directory` is harmless:
    /// a folder (trailing `/`) whose own name is in `folders`, or a file whose name is in the file list.
    ///
    /// A file inside a regenerable folder that git lists on its own does not count as harmless: git only
    /// lists it separately when the folder itself is not ignored, so it is not plain build output.
    public static func isHarmlessIgnoredPath(_ path: String) -> Bool {
        if path.hasSuffix("/") {
            let name = path.dropLast().split(separator: "/").last.map(String.init) ?? ""
            return isRegenerableFolder(name)
        }
        let name = path.split(separator: "/").last.map(String.init) ?? path
        return isHarmlessFile(name)
    }
}
