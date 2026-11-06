import Foundation

/// Reads `xcrun simctl ... -j` output leniently: a field of the wrong type, or a missing one, becomes nil
/// instead of failing the whole decode. Only output that is not the expected kind of JSON at all throws.
enum SimctlParser {
    struct ParseError: Error, CustomStringConvertible {
        var description: String
    }

    /// Devices with `isAvailable == false`, from `simctl list devices -j`
    /// (`{"devices": {"<runtime identifier>": [{...}]}}`). A device without a name or udid is skipped.
    static func unavailableDevices(from data: Data) throws -> [SimulatorDevice] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let groups = root["devices"] as? [String: Any]
        else { throw ParseError(description: "simctl list devices: unexpected output") }

        var devices: [SimulatorDevice] = []
        for runtime in groups.keys.sorted() {
            for entry in (groups[runtime] as? [Any]) ?? [] {
                guard let device = entry as? [String: Any],
                      bool(device["isAvailable"]) == false,
                      let name = string(device["name"]),
                      let udid = string(device["udid"])
                else { continue }
                devices.append(SimulatorDevice(
                    name: name,
                    udid: udid,
                    runtime: runtime,
                    sizeBytes: int64(device["dataPathSize"])
                ))
            }
        }
        // Biggest first, so the list reads like the space it would free.
        return devices.sorted { lhs, rhs in
            let left = lhs.sizeBytes ?? 0
            let right = rhs.sizeBytes ?? 0
            return left != right ? left > right : lhs.udid < rhs.udid
        }
    }

    /// Runtimes from `simctl runtime list -j`: a dictionary keyed by identifier. Entries that are not
    /// objects are skipped. Biggest first; runtimes without a size last.
    static func runtimes(from data: Data) throws -> [SimulatorRuntime] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError(description: "simctl runtime list: unexpected output")
        }
        let runtimes = root.compactMap { key, value -> SimulatorRuntime? in
            guard let entry = value as? [String: Any] else { return nil }
            return SimulatorRuntime(
                identifier: key,
                runtimeIdentifier: string(entry["runtimeIdentifier"]),
                version: string(entry["version"]),
                build: string(entry["build"]),
                kind: string(entry["kind"]),
                deletable: bool(entry["deletable"]),
                lastUsedAt: date(entry["lastUsedAt"]),
                sizeBytes: int64(entry["sizeBytes"])
            )
        }
        return runtimes.sorted { lhs, rhs in
            switch (lhs.sizeBytes, rhs.sizeBytes) {
            case let (left?, right?) where left != right: left > right
            case (_?, nil): true
            case (nil, _?): false
            default: lhs.identifier < rhs.identifier
            }
        }
    }

    // MARK: Lenient field readers

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    /// A JSON boolean, or the strings older Xcodes print (`YES`/`NO`/`true`/`false`).
    private static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            return number.boolValue
        case let text as String:
            switch text.lowercased() {
            case "yes", "true": return true
            case "no", "false": return false
            default: return nil
            }
        default:
            return nil
        }
    }

    private static func int64(_ value: Any?) -> Int64? {
        switch value {
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID():
            return number.int64Value
        case let text as String:
            return Int64(text)
        default:
            return nil
        }
    }

    /// `2026-11-06T06:09:20Z`, with or without fractional seconds.
    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}
