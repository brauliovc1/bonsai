import Foundation

/// What the iOS Simulator costs in disk space. Read-only.
public struct SimulatorReport: Sendable, Codable, Equatable {
    public enum State: String, Sendable, Codable {
        /// `xcode-select -p` fails or `xcrun` is missing: nothing is scanned and nothing can be cleaned.
        case noXcode
        case available
    }

    public var state: State
    /// `<home>/Library/Developer/CoreSimulator/Devices`; nil when the folder is missing.
    public var devicesBytes: Int64?
    /// `<home>/Library/Developer/CoreSimulator/Caches`; nil when the folder is missing.
    public var cachesBytes: Int64?
    /// Devices whose runtime is gone. `xcrun simctl delete unavailable` removes exactly these.
    public var unavailableDevices: [SimulatorDevice]
    /// Installed runtimes, biggest first. Shown only; clean-claude never deletes a runtime.
    public var runtimes: [SimulatorRuntime]
    /// Things that went wrong without stopping the scan.
    public var warnings: [String]

    public init(
        state: State,
        devicesBytes: Int64? = nil,
        cachesBytes: Int64? = nil,
        unavailableDevices: [SimulatorDevice] = [],
        runtimes: [SimulatorRuntime] = [],
        warnings: [String] = []
    ) {
        self.state = state
        self.devicesBytes = devicesBytes
        self.cachesBytes = cachesBytes
        self.unavailableDevices = unavailableDevices
        self.runtimes = runtimes
        self.warnings = warnings
    }

    /// What `simctl delete unavailable` would remove, from the devices' own data sizes.
    public var unavailableDevicesBytes: Int64 {
        unavailableDevices.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
    }
}

/// A simulator device that cannot boot because its runtime is not installed.
public struct SimulatorDevice: Sendable, Codable, Hashable, Identifiable {
    public var name: String
    public var udid: String
    /// The runtime identifier simctl files the device under, e.g. `com.apple.CoreSimulator.SimRuntime.iOS-17-5`.
    public var runtime: String
    /// simctl's `dataPathSize`, when it reports one.
    public var sizeBytes: Int64?

    public init(name: String, udid: String, runtime: String, sizeBytes: Int64? = nil) {
        self.name = name
        self.udid = udid
        self.runtime = runtime
        self.sizeBytes = sizeBytes
    }

    public var id: String { udid }

    /// `iOS 17.5` for the runtime above.
    public var runtimeName: String { SimulatorRuntime.displayName(forRuntimeIdentifier: runtime) }
}
