import Foundation

/// How Claude names the folders under `<claude config>/projects` (PLAN §4.3): the working folder's
/// absolute path with every character outside `[A-Za-z0-9]` replaced by `-`.
///
/// The rule was verified on a real Mac for `/` and `.`; it is not a documented format. It is applied per
/// UTF-16 code unit, like the JavaScript replace Claude uses, so an emoji becomes two dashes.
public enum ClaudeProjectFolderName {
    public static func encode(_ path: String) -> String {
        let dash: UInt16 = 0x2D
        let units = path.utf16.map { isAlphanumeric($0) ? $0 : dash }
        return String(decoding: units, as: UTF16.self)
    }

    /// Folder name -> path, for every candidate path that encodes to it. A name that two different
    /// candidates encode to (`/a/b-c` and `/a/b/c`) is left out: guessing would put a wrong path on
    /// screen, so those folders keep their raw name.
    public static func decodingTable(candidates: [String]) -> [String: String] {
        var pathsByName: [String: Set<String>] = [:]
        for path in candidates {
            pathsByName[encode(path), default: []].insert(path)
        }
        return pathsByName.compactMapValues { paths in
            paths.count == 1 ? paths.first : nil
        }
    }

    private static func isAlphanumeric(_ unit: UInt16) -> Bool {
        (0x30...0x39).contains(unit) || (0x41...0x5A).contains(unit) || (0x61...0x7A).contains(unit)
    }
}
