import XCTest
@testable import LuxaforPresence

final class LightOutputControllerTests: XCTestCase {
    func test_blink_startsOnColorAndAlternatesOnOneInjectedTimer() {
        let client = ControllerFakeClient()
        let timer = ControllerFakeTimer()
        let controller = makeController(client: client, timer: timer)
        var outputs: [LightOutput] = []
        controller.onOutputChange = { outputs.append($0) }

        controller.apply(.blink(color: .red, interval: 0.75))

        XCTAssertEqual(controller.desiredOutput, .blink(color: .red, interval: 0.75))
        XCTAssertEqual(outputs, [.blink(color: .red, interval: 0.75)])
        XCTAssertEqual(client.actions, [.init(color: .red, userId: "user", force: false)])
        XCTAssertEqual(timer.scheduledIntervals, [0.75])

        timer.fire()
        timer.fire()

        XCTAssertEqual(
            client.actions,
            [
                .init(color: .red, userId: "user", force: false),
                .init(color: .off, userId: "user", force: false),
                .init(color: .red, userId: "user", force: false),
            ]
        )
        XCTAssertEqual(timer.scheduledIntervals, [0.75])
    }

    func test_duplicateLogicalOutput_preservesCadenceAndSuppressesOutputCallback() {
        let client = ControllerFakeClient()
        let timer = ControllerFakeTimer()
        let controller = makeController(client: client, timer: timer)
        var callbackCount = 0
        controller.onOutputChange = { _ in callbackCount += 1 }
        let output = LightOutput.blink(color: .red, interval: 0.75)

        controller.apply(output)
        controller.apply(output)

        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(client.actions.count, 1)
        XCTAssertEqual(timer.scheduledIntervals, [0.75])
        XCTAssertEqual(timer.cancelCount, 1)
    }

    func test_logicalTransitionWithSamePhysicalPhase_doesNotResendColor() {
        let client = ControllerFakeClient()
        let timer = ControllerFakeTimer()
        let controller = makeController(client: client, timer: timer)
        var outputs: [LightOutput] = []
        controller.onOutputChange = { outputs.append($0) }

        controller.apply(.blink(color: .red, interval: 0.75))
        controller.apply(.solid(.red))

        XCTAssertEqual(
            outputs,
            [.blink(color: .red, interval: 0.75), .solid(.red)]
        )
        XCTAssertEqual(client.actions, [.init(color: .red, userId: "user", force: false)])
        XCTAssertNil(timer.handler)
    }

    func test_staleTimerCallbackCannotOverwriteNewerOutput() {
        let client = ControllerFakeClient()
        let timer = ControllerFakeTimer()
        let controller = makeController(client: client, timer: timer)

        controller.apply(.blink(color: .red, interval: 0.75))
        let staleHandler = timer.handler
        controller.apply(.solid(.yellow))
        staleHandler?()

        XCTAssertEqual(
            client.actions,
            [
                .init(color: .red, userId: "user", force: false),
                .init(color: .yellow, userId: "user", force: false),
            ]
        )
        XCTAssertEqual(controller.desiredOutput, .solid(.yellow))
    }

    func test_suspendAcceptsNewLogicalOutputWithoutSendingUntilResume() {
        let client = ControllerFakeClient()
        let timer = ControllerFakeTimer()
        let controller = makeController(client: client, timer: timer)
        var outputs: [LightOutput] = []
        controller.onOutputChange = { outputs.append($0) }

        controller.apply(.blink(color: .red, interval: 0.75))
        let staleHandler = timer.handler
        controller.suspend()
        staleHandler?()
        controller.apply(.solid(.yellow))

        XCTAssertEqual(client.actions, [.init(color: .red, userId: "user", force: false)])
        XCTAssertEqual(controller.desiredOutput, .solid(.yellow))
        XCTAssertEqual(
            outputs,
            [.blink(color: .red, interval: 0.75), .solid(.yellow)]
        )

        controller.resume()

        XCTAssertEqual(
            client.actions,
            [
                .init(color: .red, userId: "user", force: false),
                .init(color: .yellow, userId: "user", force: true),
            ]
        )
        XCTAssertNil(timer.handler)
    }

    func test_resumeRestartsBlinkOnColorAndReplacesTimerSchedule() {
        let client = ControllerFakeClient()
        let timer = ControllerFakeTimer()
        let controller = makeController(client: client, timer: timer)

        controller.apply(.blink(color: .red, interval: 0.5))
        timer.fire()
        controller.suspend()
        controller.resume()

        XCTAssertEqual(
            client.actions,
            [
                .init(color: .red, userId: "user", force: false),
                .init(color: .off, userId: "user", force: false),
                .init(color: .red, userId: "user", force: true),
            ]
        )
        XCTAssertEqual(timer.scheduledIntervals, [0.5, 0.5])
    }

    func test_reassertForcesCurrentBlinkPhaseWithoutResettingCadence() {
        let client = ControllerFakeClient()
        let timer = ControllerFakeTimer()
        let controller = makeController(client: client, timer: timer)

        controller.apply(.blink(color: .red, interval: 0.75))
        timer.fire()
        controller.reassert()

        XCTAssertEqual(
            client.actions,
            [
                .init(color: .red, userId: "user", force: false),
                .init(color: .off, userId: "user", force: false),
                .init(color: .off, userId: "user", force: true),
            ]
        )
        XCTAssertEqual(timer.scheduledIntervals, [0.75])
    }

    func test_shutdownCancelsBlinkForcesOffAndRejectsLaterWork() {
        let client = ControllerFakeClient()
        let timer = ControllerFakeTimer()
        let controller = makeController(client: client, timer: timer)
        var outputs: [LightOutput] = []
        controller.onOutputChange = { outputs.append($0) }

        controller.apply(.blink(color: .red, interval: 0.75))
        let staleHandler = timer.handler
        controller.shutdown()
        staleHandler?()
        controller.apply(.solid(.yellow))
        controller.reassert()
        controller.resume()
        controller.shutdown()

        XCTAssertEqual(controller.desiredOutput, .off)
        XCTAssertEqual(outputs, [.blink(color: .red, interval: 0.75), .off])
        XCTAssertEqual(
            client.actions,
            [
                .init(color: .red, userId: "user", force: false),
                .init(color: .off, userId: "user", force: true),
            ]
        )
        XCTAssertNil(timer.handler)
    }

    func test_reentrantOutputCallbackCannotActivateSupersededOutput() {
        let client = ControllerFakeClient()
        let timer = ControllerFakeTimer()
        var controller: LightOutputController!
        controller = makeController(client: client, timer: timer)
        controller.onOutputChange = { output in
            if output == .blink(color: .red, interval: 0.75) {
                controller.apply(.solid(.yellow))
            }
        }

        controller.apply(.blink(color: .red, interval: 0.75))

        XCTAssertEqual(controller.desiredOutput, .solid(.yellow))
        XCTAssertEqual(client.actions, [.init(color: .yellow, userId: "user", force: false)])
        XCTAssertTrue(timer.scheduledIntervals.isEmpty)
    }

    func test_invalidBlinkIntervalDoesNotScheduleBusyTimer() {
        let client = ControllerFakeClient()
        let timer = ControllerFakeTimer()
        let controller = makeController(client: client, timer: timer)

        controller.apply(.blink(color: .red, interval: 0))

        XCTAssertEqual(client.actions, [.init(color: .red, userId: "user", force: false)])
        XCTAssertTrue(timer.scheduledIntervals.isEmpty)
    }

    private func makeController(
        client: ControllerFakeClient,
        timer: ControllerFakeTimer
    ) -> LightOutputController {
        LightOutputController(client: client, userId: "user", timer: timer)
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

private final class ControllerFakeTimer: LightOutputTimerProtocol {
    private(set) var scheduledIntervals: [TimeInterval] = []
    private(set) var cancelCount = 0
    private(set) var handler: (() -> Void)?

    func schedule(every interval: TimeInterval, handler: @escaping () -> Void) {
        scheduledIntervals.append(interval)
        self.handler = handler
    }

    func cancel() {
        cancelCount += 1
        handler = nil
    }

    func fire() {
        handler?()
    }
}
