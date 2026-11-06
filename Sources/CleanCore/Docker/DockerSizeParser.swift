import Foundation

/// Reads the sizes `docker system df` prints: decimal units, no space, e.g. `12.3GB`, `1.2kB`, `0B`, and
/// the reclaimable column's `512MB (40%)`.
public enum DockerSizeParser {
    private static let multipliers: [String: Double] = [
        "B": 1,
        "KB": 1e3,
        "MB": 1e6,
        "GB": 1e9,
        "TB": 1e12,
        "PB": 1e15,
    ]

    /// Bytes for a docker size string, or nil when it is not one.
    public static func bytes(from text: String) -> Int64? {
        // Drop the trailing "(40%)" of the reclaimable column.
        let size = text.prefix { $0 != "(" }.trimmingCharacters(in: .whitespaces)
        let number = size.prefix { $0.isASCII && ($0.isNumber || $0 == ".") }
        let unit = size.dropFirst(number.count).trimmingCharacters(in: .whitespaces).uppercased()
        guard !number.isEmpty,
              let value = Double(number), value.isFinite,
              let multiplier = multipliers[unit]
        else { return nil }
        let bytes = (value * multiplier).rounded()
        guard bytes < Double(Int64.max) else { return nil }
        return Int64(bytes)
    }
}
