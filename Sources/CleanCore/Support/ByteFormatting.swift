import Foundation

/// Human-readable byte counts with one decimal, in binary units (1 KB = 1024 bytes), like `du -h`.
public enum ByteFormatting {
    private static let units = ["KB", "MB", "GB", "TB", "PB"]

    public static func string(_ bytes: Int64) -> String {
        var value = Double(max(bytes, 0)) / 1024
        var unit = 0
        while value >= 1024, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        return String(format: "%.1f %@", value, units[unit])
    }
}
