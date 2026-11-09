import Foundation

enum StandardError {
    static func write(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
