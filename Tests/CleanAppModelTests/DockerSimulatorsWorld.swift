@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation

/// A fake home, the scripted toolchain, an app model on them, and the Docker & Simulators model.
@MainActor
struct DockerSimulatorsWorld {
    let home: FakeHome
    let toolchain: FakeToolchain
    let app: AppModel
    let model: DockerSimulatorsModel

    init(
        docker: Bool = true,
        xcrun: Bool = true,
        developerTools: Bool = true,
        configure: (inout CleanEnvironment) -> Void = { _ in }
    ) throws {
        home = try FakeHome()
        toolchain = FakeToolchain()
        var environment = home.environment().withFakeTools(docker: docker, xcrun: xcrun, developerTools: developerTools)
        configure(&environment)
        app = AppModel(environment: environment)
        model = DockerSimulatorsModel(app: app, runner: toolchain.runner)
    }
}
