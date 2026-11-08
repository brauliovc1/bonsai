import Foundation

/// Free space for the menu bar: whole gigabytes ("31 GB"), one decimal under 10 GB ("9.4 GB"). The same unit
/// as every other size in the app (`ByteFormatting`: 1 GB = 1024³ bytes), so the menu bar and the Overview
/// agree; the low-space warning counts in it too.
public enum FreeSpaceText {
    public static let gigabyte: Double = 1024 * 1024 * 1024

    /// "31 GB", "9.4 GB", "0.3 GB", or "–" when unknown.
    public static func label(_ bytes: Int64?) -> String {
        guard let bytes else { return "–" }
        let gigabytes = Double(max(bytes, 0)) / gigabyte
        if gigabytes < 9.95 {
            return String(format: "%.1f GB", gigabytes)
        }
        return String(format: "%.0f GB", gigabytes.rounded())
    }

    /// True when `bytes` is below `warningGB` gigabytes. Unknown space is not low.
    public static func isLow(_ bytes: Int64?, warningGB: Int) -> Bool {
        guard let bytes else { return false }
        return Double(bytes) < Double(warningGB) * gigabyte
    }
}
