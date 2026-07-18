import XCTest
@testable import LuxaforPresence

final class LightOutputControllerTests: XCTestCase {
    func test_applySolidColor_sendsColorAndPublishesLogicalOutput() {
        let client = ControllerFakeClient()
        let controller = makeController(client: client)
        var outputs: [LightOutput] = []
        controller.onOutputChange = { outputs.append($0) }

        controller.apply(.solid(.red))

        XCTAssertEqual(controller.desiredOutput, .solid(.red))
        XCTAssertEqual(outputs, [.solid(.red)])
        XCTAssertEqual(
            client.actions,
            [.init(color: .red, userId: "user", force: false)]
        )
    }

    func test_duplicateLogicalOutput_suppressesTransportAndCallback() {
        let client = ControllerFakeClient()
        let controller = makeController(client: client)
        var callbackCount = 0
        controller.onOutputChange = { _ in callbackCount += 1 }

        controller.apply(.solid(.red))
        controller.apply(.solid(.red))

        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(client.actions.count, 1)
    }

    func test_suspendAcceptsNewLogicalOutputWithoutSendingUntilResume() {
        let client = ControllerFakeClient()
        let controller = makeController(client: client)
        var outputs: [LightOutput] = []
        controller.onOutputChange = { outputs.append($0) }

        controller.apply(.solid(.red))
        controller.suspend()
        controller.apply(.solid(.yellow))

        XCTAssertEqual(
            client.actions,
            [.init(color: .red, userId: "user", force: false)]
        )
        XCTAssertEqual(controller.desiredOutput, .solid(.yellow))
        XCTAssertEqual(outputs, [.solid(.red), .solid(.yellow)])

        controller.resume()

        XCTAssertEqual(
            client.actions,
            [
                .init(color: .red, userId: "user", force: false),
                .init(color: .yellow, userId: "user", force: true),
            ]
        )
    }

    func test_reassertForcesCurrentColor() {
        let client = ControllerFakeClient()
        let controller = makeController(client: client)

        controller.apply(.solid(.orange))
        controller.reassert()

        XCTAssertEqual(
            client.actions,
            [
                .init(color: .orange, userId: "user", force: false),
                .init(color: .orange, userId: "user", force: true),
            ]
        )
    }

    func test_shutdownForcesOffAndRejectsLaterWork() {
        let client = ControllerFakeClient()
        let controller = makeController(client: client)
        var outputs: [LightOutput] = []
        controller.onOutputChange = { outputs.append($0) }

        controller.apply(.solid(.red))
        controller.shutdown()
        controller.apply(.solid(.yellow))
        controller.reassert()
        controller.resume()
        controller.shutdown()

        XCTAssertEqual(controller.desiredOutput, .off)
        XCTAssertEqual(outputs, [.solid(.red), .off])
        XCTAssertEqual(
            client.actions,
            [
                .init(color: .red, userId: "user", force: false),
                .init(color: .off, userId: "user", force: true),
            ]
        )
    }

    func test_reentrantOutputCallbackCannotActivateSupersededOutput() {
        let client = ControllerFakeClient()
        var controller: LightOutputController!
        controller = makeController(client: client)
        controller.onOutputChange = { output in
            if output == .solid(.red) {
                controller.apply(.solid(.yellow))
            }
        }

        controller.apply(.solid(.red))

        XCTAssertEqual(controller.desiredOutput, .solid(.yellow))
        XCTAssertEqual(
            client.actions,
            [.init(color: .yellow, userId: "user", force: false)]
        )
    }

    private func makeController(client: ControllerFakeClient) -> LightOutputController {
        LightOutputController(client: client, userId: "user")
    }
}

private final class ControllerFakeClient: LuxaforClientProtocol {
    struct Action: Equatable {
        let color: LuxaforColor
        let userId: String
        let force: Bool
    }

    private(set) var actions: [Action] = []

    func setSolidColor(_ color: LuxaforColor, userId: String, force: Bool) {
        actions.append(.init(color: color, userId: userId, force: force))
    }
}
