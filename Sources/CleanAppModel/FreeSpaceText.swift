import Foundation

/// Free space for the menu bar's tooltip: whole gigabytes ("31 GB"), one decimal under 10 GB ("9.4 GB"). The
/// same unit as every other size in the app (`ByteFormatting`: 1 GB = 1024³ bytes), so the menu bar and the
/// Overview agree; the low-space warning counts in it too.
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

    /// True when `bytes` is below half of `warningGB` gigabytes.
    public static func isVeryLow(_ bytes: Int64?, warningGB: Int) -> Bool {
        guard let bytes else { return false }
        return Double(bytes) < Double(warningGB) * gigabyte / 2
    }

    /// The menu window's line: "23.0 GB free of 460 GB (95% used)"; "Free space unknown" without a reading.
    public static func summary(free: Int64?, total: Int64?) -> String {
        guard let free else { return "Free space unknown" }
        guard let total, total > 0 else { return "\(DisplayText.bytes(free)) free" }
        let used = Double(total - free) / Double(total)
        return "\(DisplayText.bytes(free)) free of \(label(total)) (\(Int((used * 100).rounded()))% used)"
    }
}
