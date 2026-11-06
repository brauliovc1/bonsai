import Foundation

/// Dates as the CLI prints them: local time, `2026-11-06 14:05`.
enum DateText {
    static func short(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
