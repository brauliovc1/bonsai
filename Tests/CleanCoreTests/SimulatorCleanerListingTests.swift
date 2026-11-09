@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// Wave 4: `simctl delete unavailable` can't be limited, so the devices are listed again right before it
/// starts, and it runs only when they are exactly the confirmed ones.
@Suite("SimulatorCleaner: the list right before the delete")
struct SimulatorCleanerListingTests {
    private static let xcrun = URL(fileURLWithPath: "/fake/bin/xcrun")
    private let logFolder: TemporaryDirectory

    init() throws {
        logFolder = try TemporaryDirectory(prefix: "bonsai-simulator-listing")
    }

    private func cleaner(_ runner: ScriptedCommandRunner) -> SimulatorCleaner {
        SimulatorCleaner(
            xcrun: Self.xcrun, runner: runner.runner, freeSpace: ScriptedFreeSpace([1, 1]).probe,
            log: RemovalLog(directory: logFolder.url)
        )
    }

    private func devices(_ unavailable: [String]) -> String {
        let entries = unavailable.map {
            #"{ "dataPathSize" : 10, "udid" : "\#($0)", "isAvailable" : false, "name" : "Device \#($0)", "state" : "Shutdown" }"#
        }.joined(separator: ",")
        return #"{ "devices" : { "com.apple.CoreSimulator.SimRuntime.iOS-17-5" : [ \#(entries) ] } }"#
    }

    private func confirmed(_ udids: [String]) -> [SimulatorDevice] {
        udids.map { SimulatorDevice(name: "Device \($0)", udid: $0, runtime: "iOS-17-5") }
    }

    private func isListing(_ call: ScriptedCommandRunner.Call) -> Bool { call.arguments == ["simctl", "list", "devices", "-j"] }
    private func isDelete(_ call: ScriptedCommandRunner.Call) -> Bool { call.arguments == ["simctl", "delete", "unavailable"] }

    @Test func theSameDevicesRunTheDeleteRightAfterOneDevicesOnlyListing() async throws {
        let runner = ScriptedCommandRunner { [self] call in
            ScriptedCommandRunner.result(stdout: isListing(call) ? devices(["B", "C"]) : "")
        }

        let outcome = try await cleaner(runner).run(ifConfirmed: true, estimatedBytes: 20, onlyDeleting: confirmed(["C", "B"]))

        #expect(outcome?.succeeded == true)
        #expect(runner.calls.map(\.arguments) == [["simctl", "list", "devices", "-j"], ["simctl", "delete", "unavailable"]],
                "one listing (no runtime list, no sizes), then the delete")
    }

    @Test func aDeviceThatBecameUnavailableStopsTheDelete() async throws {
        let runner = ScriptedCommandRunner { [self] call in
            ScriptedCommandRunner.result(stdout: isListing(call) ? devices(["B", "C", "D"]) : "")
        }

        do {
            _ = try await cleaner(runner).run(ifConfirmed: true, onlyDeleting: confirmed(["B", "C"]))
            Issue.record("expected a refusal")
        } catch let refusal as SimulatorCleaner.Refusal {
            #expect(refusal == .listChanged(added: ["D"], gone: []))
            #expect(refusal.description.contains("1 more would be deleted now"))
        }
        #expect(!runner.calls.contains(where: isDelete))
        #expect(try RemovalLog(directory: logFolder.url).entries().isEmpty)
    }

    @Test func aListedDeviceThatIsNoLongerUnavailableStopsTheDelete() async throws {
        let runner = ScriptedCommandRunner { [self] call in
            ScriptedCommandRunner.result(stdout: isListing(call) ? devices(["B"]) : "")
        }

        do {
            _ = try await cleaner(runner).run(ifConfirmed: true, onlyDeleting: confirmed(["B", "C"]))
            Issue.record("expected a refusal")
        } catch let refusal as SimulatorCleaner.Refusal {
            #expect(refusal == .listChanged(added: [], gone: ["C"]))
        }
        #expect(!runner.calls.contains(where: isDelete))
    }

    @Test func aListingThatFailsRunsNothing() async throws {
        for failing in [
            ScriptedCommandRunner.result(exitCode: 1, stderr: "simctl is broken"),
            ScriptedCommandRunner.result(stdout: "not json"),
        ] {
            let runner = ScriptedCommandRunner { _ in failing }
            do {
                _ = try await cleaner(runner).run(ifConfirmed: true, onlyDeleting: [])
                Issue.record("expected a refusal")
            } catch let refusal as SimulatorCleaner.Refusal {
                guard case .listFailed = refusal else {
                    Issue.record("expected listFailed, got \(refusal)")
                    continue
                }
            }
            #expect(!runner.calls.contains(where: isDelete))
        }
        let cannotStart = ScriptedCommandRunner { _ in throw ScriptedCommandRunner.StartFailure() }
        await #expect(throws: SimulatorCleaner.Refusal.self) {
            _ = try await cleaner(cannotStart).run(ifConfirmed: true, onlyDeleting: [])
        }
    }

    @Test func withoutConfirmationNothingIsListedOrRun() async throws {
        let runner = ScriptedCommandRunner { _ in ScriptedCommandRunner.result() }
        let outcome = try await cleaner(runner).run(ifConfirmed: false, onlyDeleting: confirmed(["B"]))
        #expect(outcome == nil)
        #expect(runner.calls.isEmpty)
    }
}
