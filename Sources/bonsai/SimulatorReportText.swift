import CleanCore
import Foundation

/// The `simulators` command's report as text.
struct SimulatorReportText {
    let report: SimulatorReport
    let now: Date

    func render() -> String {
        guard report.state == .available else {
            return "Simulators: no Xcode found (xcode-select -p fails), so nothing was scanned."
        }
        let base = "~/Library/Developer/CoreSimulator"
        var lines = [
            "Simulators: Xcode found",
            "Devices: \(size(report.devicesBytes))  \(base)/Devices",
            "Caches:  \(size(report.cachesBytes))  \(base)/Caches",
            "",
        ]
        lines += unavailableLines()
        lines.append("")
        lines += runtimeLines()
        return lines.joined(separator: "\n")
    }

    private func size(_ bytes: Int64?) -> String {
        bytes.map(ByteFormatting.string) ?? "-"
    }

    private func unavailableLines() -> [String] {
        let devices = report.unavailableDevices
        guard !devices.isEmpty else { return ["Unavailable devices: none"] }
        var rows = [["DEVICE", "RUNTIME", "SIZE", "UDID"]]
        for device in devices {
            rows.append([device.name, device.runtimeName, size(device.sizeBytes), device.udid])
        }
        return ["Unavailable devices: \(devices.count), about \(ByteFormatting.string(report.unavailableDevicesBytes))"]
            + AlignedColumns.lines(rows, rightAligned: [2]).map { "  " + $0 }
    }

    private func runtimeLines() -> [String] {
        guard !report.runtimes.isEmpty else { return ["Runtimes: none found"] }
        var rows = [["RUNTIME", "KIND", "SIZE", "LAST USED", "DELETABLE"]]
        for runtime in report.runtimes {
            rows.append([
                runtime.displayName,
                runtime.kind ?? "-",
                size(runtime.sizeBytes),
                runtime.lastUsedAt.map(lastUsed) ?? "-",
                runtime.deletable.map { $0 ? "yes" : "no" } ?? "-",
            ])
        }
        return ["Runtimes (shown only; remove them in Xcode's Settings, Bonsai never does):"]
            + AlignedColumns.lines(rows, rightAligned: [2]).map { "  " + $0 }
    }

    private func lastUsed(_ date: Date) -> String {
        let days = max(0, Int(now.timeIntervalSince(date) / 86_400))
        return days == 0 ? "today" : "\(days) d ago"
    }
}
