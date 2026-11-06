import Foundation

/// One line of `docker system df`: Images, Containers, Local Volumes or Build Cache.
public struct DockerUsageRow: Sendable, Codable, Hashable, Identifiable {
    public var type: String
    public var total: Int
    public var active: Int
    public var sizeBytes: Int64
    /// What docker says could be reclaimed. For images this counts every unused image, which
    /// `docker system prune -f` (no `-a`) does not remove.
    public var reclaimableBytes: Int64

    public init(type: String, total: Int, active: Int, sizeBytes: Int64, reclaimableBytes: Int64) {
        self.type = type
        self.total = total
        self.active = active
        self.sizeBytes = sizeBytes
        self.reclaimableBytes = reclaimableBytes
    }

    public var id: String { type }

    /// Parsed from `docker system df --format '{{json .}}'`: one JSON object per line, every value a
    /// string (`Type`, `TotalCount`, `Active`, `Size`, `Reclaimable`).
    ///
    /// Blank lines are ignored; a line that is not JSON, has no `Type`, or has an unreadable `Size` or
    /// `Reclaimable` is counted in `skippedLines`, so one odd line never hides the rest.
    public static func parse(_ output: String) -> (rows: [DockerUsageRow], skippedLines: Int) {
        var rows: [DockerUsageRow] = []
        var skipped = 0
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if let row = row(fromJSONLine: trimmed) {
                rows.append(row)
            } else {
                skipped += 1
            }
        }
        return (rows, skipped)
    }

    private static func row(fromJSONLine line: String) -> DockerUsageRow? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let type = text(object["Type"]), !type.isEmpty,
              let sizeBytes = text(object["Size"]).flatMap(DockerSizeParser.bytes(from:)),
              let reclaimableBytes = text(object["Reclaimable"]).flatMap(DockerSizeParser.bytes(from:))
        else { return nil }
        return DockerUsageRow(
            type: type,
            total: text(object["TotalCount"]).flatMap { Int($0) } ?? 0,
            active: text(object["Active"]).flatMap { Int($0) } ?? 0,
            sizeBytes: sizeBytes,
            reclaimableBytes: reclaimableBytes
        )
    }

    /// A JSON string, or a JSON number written out; nil for anything else.
    private static func text(_ value: Any?) -> String? {
        switch value {
        case let string as String: string
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }
}
