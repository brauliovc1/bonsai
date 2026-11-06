@testable import CleanCore
import Foundation
import Testing

@Suite("simctl output parsing")
struct SimctlParserTests {
    static let devicesJSON = """
        {
          "devices" : {
            "com.apple.CoreSimulator.SimRuntime.iOS-17-5" : [
              {
                "dataPath" : "\\/Users\\/me\\/Library\\/Developer\\/CoreSimulator\\/Devices\\/AAAA\\/data",
                "dataPathSize" : 1368854528,
                "udid" : "AAAA",
                "isAvailable" : true,
                "name" : "iPhone 15 Pro",
                "state" : "Shutdown"
              },
              {
                "dataPathSize" : 123456,
                "udid" : "BBBB",
                "isAvailable" : false,
                "availabilityError" : "runtime profile not found using \\"System\\" match policy",
                "name" : "iPhone 15",
                "state" : "Shutdown"
              }
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-16-4" : [
              {
                "udid" : "CCCC",
                "isAvailable" : "NO",
                "name" : "iPad Air",
                "state" : "Shutdown"
              },
              {
                "udid" : "DDDD",
                "isAvailable" : false,
                "state" : "Shutdown"
              },
              {
                "isAvailable" : false,
                "name" : "No udid"
              }
            ],
            "com.apple.CoreSimulator.SimRuntime.watchOS-10-0" : [
              { "udid" : "EEEE", "name" : "Apple Watch", "state" : "Shutdown" }
            ]
          }
        }
        """

    @Test func listsOnlyUnavailableDevicesWithTheirRuntime() throws {
        let devices = try SimctlParser.unavailableDevices(from: Data(Self.devicesJSON.utf8))

        // Biggest first; a device with no size sorts last.
        #expect(devices == [
            SimulatorDevice(
                name: "iPhone 15",
                udid: "BBBB",
                runtime: "com.apple.CoreSimulator.SimRuntime.iOS-17-5",
                sizeBytes: 123_456
            ),
            SimulatorDevice(
                name: "iPad Air",
                udid: "CCCC",
                runtime: "com.apple.CoreSimulator.SimRuntime.iOS-16-4",
                sizeBytes: nil
            ),
        ])
        #expect(devices.map(\.runtimeName) == ["iOS 17.5", "iOS 16.4"])
    }

    @Test func noUnavailableDevicesIsAnEmptyList() throws {
        let json = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-17-5":[{"udid":"A","name":"x","isAvailable":true}]}}"#
        #expect(try SimctlParser.unavailableDevices(from: Data(json.utf8)).isEmpty)
        #expect(try SimctlParser.unavailableDevices(from: Data(#"{"devices":{}}"#.utf8)).isEmpty)
    }

    @Test func devicesOutputThatIsNotTheExpectedJSONThrows() {
        for text in ["", "not json", "[]", #"{"runtimes":[]}"#, #"{"devices":[]}"#] {
            #expect(throws: SimctlParser.ParseError.self) {
                _ = try SimctlParser.unavailableDevices(from: Data(text.utf8))
            }
        }
    }

    static let runtimesJSON = """
        {
          "905CF5D6-411E-4920-956C-1C73C6CD86D2" : {
            "build" : "24A434",
            "deletable" : true,
            "identifier" : "905CF5D6-411E-4920-956C-1C73C6CD86D2",
            "kind" : "Patchable Cryptex Disk Image",
            "lastUsedAt" : "2026-11-06T06:09:20Z",
            "mountPath" : "\\/private\\/var\\/run\\/mnt",
            "platformIdentifier" : "com.apple.platform.iphonesimulator",
            "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            "signatureState" : "Unknown",
            "sizeBytes" : 8067000161,
            "state" : "Ready",
            "supportedArchitectures" : [ "arm64" ],
            "version" : "27.0"
          },
          "483725E5-2C48-411D-B950-DB914DB68834" : {
            "build" : "21F79",
            "deletable" : false,
            "kind" : "Disk Image",
            "lastUsedAt" : "2026-10-27T05:14:42.500Z",
            "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.iOS-17-5",
            "sizeBytes" : 7336630623,
            "version" : "17.5"
          },
          "F0F0F0F0-0000-0000-0000-000000000000" : {
            "build" : "22A1",
            "deletable" : true,
            "kind" : "Bundle",
            "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.watchOS-11-0",
            "state" : "Downloading",
            "version" : "11.0"
          },
          "11111111-0000-0000-0000-000000000000" : { },
          "not-an-entry" : "just a string",
          "also-not-an-entry" : [ 1, 2, 3 ]
        }
        """

    @Test func decodesRuntimesLeniently() throws {
        let runtimes = try SimctlParser.runtimes(from: Data(Self.runtimesJSON.utf8))

        // Biggest first, runtimes without a size last (by identifier). Non-object entries are skipped.
        #expect(runtimes.map(\.identifier) == [
            "905CF5D6-411E-4920-956C-1C73C6CD86D2",
            "483725E5-2C48-411D-B950-DB914DB68834",
            "11111111-0000-0000-0000-000000000000",
            "F0F0F0F0-0000-0000-0000-000000000000",
        ])

        let first = runtimes[0]
        #expect(first.runtimeIdentifier == "com.apple.CoreSimulator.SimRuntime.iOS-27-0")
        #expect(first.version == "27.0")
        #expect(first.build == "24A434")
        #expect(first.kind == "Patchable Cryptex Disk Image")
        #expect(first.deletable == true)
        #expect(first.sizeBytes == 8_067_000_161)
        #expect(first.lastUsedAt == Date(timeIntervalSince1970: 1_793_945_360))
        #expect(first.displayName == "iOS 27.0 (24A434)")

        let second = runtimes[1]
        #expect(second.deletable == false)
        #expect(second.sizeBytes == 7_336_630_623)
        #expect(second.lastUsedAt != nil, "fractional seconds are accepted")

        let empty = runtimes[2]
        #expect(empty.runtimeIdentifier == nil && empty.version == nil && empty.build == nil)
        #expect(empty.kind == nil && empty.deletable == nil && empty.lastUsedAt == nil && empty.sizeBytes == nil)
        #expect(empty.displayName == "Runtime 11111111-0000-0000-0000-000000000000")

        let noSize = runtimes[3]
        #expect(noSize.sizeBytes == nil)
        #expect(noSize.kind == "Bundle")
        #expect(noSize.displayName == "watchOS 11.0 (22A1)")
    }

    @Test func wrongTypedFieldsBecomeNilInsteadOfFailing() throws {
        let json = """
            {"A":{"sizeBytes":"12345","deletable":"yes","lastUsedAt":"yesterday","version":7,"build":"","kind":null},
             "B":{"sizeBytes":true,"deletable":3,"lastUsedAt":12}}
            """
        let runtimes = try SimctlParser.runtimes(from: Data(json.utf8))
        let byID = Dictionary(uniqueKeysWithValues: runtimes.map { ($0.identifier, $0) })

        let a = try #require(byID["A"])
        #expect(a.sizeBytes == 12_345, "a numeric string is accepted")
        #expect(a.deletable == true)
        #expect(a.lastUsedAt == nil && a.version == nil && a.build == nil && a.kind == nil)

        let b = try #require(byID["B"])
        #expect(b.sizeBytes == nil && b.deletable == nil && b.lastUsedAt == nil)
    }

    @Test func runtimesOutputThatIsNotAnObjectThrows() {
        for text in ["", "nope", "[]", "42"] {
            #expect(throws: SimctlParser.ParseError.self) {
                _ = try SimctlParser.runtimes(from: Data(text.utf8))
            }
        }
        #expect((try? SimctlParser.runtimes(from: Data("{}".utf8)))?.isEmpty == true)
    }

    @Test func runtimeIdentifiersGetReadableNames() {
        #expect(SimulatorRuntime.displayName(forRuntimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-17-5") == "iOS 17.5")
        #expect(SimulatorRuntime.displayName(forRuntimeIdentifier: "com.apple.CoreSimulator.SimRuntime.xrOS-2-0") == "xrOS 2.0")
        #expect(SimulatorRuntime.displayName(forRuntimeIdentifier: "com.apple.CoreSimulator.SimRuntime.tvOS") == "tvOS")
        #expect(SimulatorRuntime.displayName(forRuntimeIdentifier: "something.else") == "something.else")
    }
}
