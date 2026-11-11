import Foundation

/// Plain text only. Invalid UTF-8 and control bytes are visible escapes, never invisible terminal commands.
public enum DiffText {
    public static func decode(_ data: Data) -> String {
        let bytes = Array(data)
        var result = ""
        var i = 0
        while i < bytes.count {
            let byte = bytes[i]
            if byte == 10 { result.append("\n"); i += 1; continue }
            if byte == 9 { result += "\\t"; i += 1; continue }
            if byte == 13 { result += "\\r"; i += 1; continue }
            if byte < 32 || byte == 127 { result += String(format: "\\x%02X", byte); i += 1; continue }
            let count = byte < 128 ? 1 : byte >= 0xC2 && byte <= 0xDF ? 2 : byte <= 0xEF && byte >= 0xE0 ? 3 : byte >= 0xF0 && byte <= 0xF4 ? 4 : 0
            if count > 0, i + count <= bytes.count, let text = String(bytes: bytes[i..<(i + count)], encoding: .utf8) {
                // Bidi and other format controls are escaped too.
                for scalar in text.unicodeScalars {
                    if scalar.properties.generalCategory == .format { result += "\\u{\(String(scalar.value, radix: 16))}" }
                    else { result.unicodeScalars.append(scalar) }
                }
                i += count
            } else { result += String(format: "\\x%02X", byte); i += 1 }
        }
        return result
    }
}
