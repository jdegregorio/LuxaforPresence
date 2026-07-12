import AVFoundation
import XCTest
@testable import LuxaforPresence

final class VoiceActivitySignalTests: XCTestCase {
    func test_startIfNeeded_afterStartFails_cleansUpAndRetries() {
        let engine = FakeVoiceActivityAudioEngine(failuresBeforeSuccess: 1)
        let signal = VoiceActivitySignal(engine: engine)

        signal.startIfNeeded()

        XCTAssertEqual(engine.events, [.installTap, .start, .stop, .removeTap])

        signal.startIfNeeded()

        XCTAssertEqual(
            engine.events,
            [.installTap, .start, .stop, .removeTap, .installTap, .start]
        )
    }

    func test_startIfNeeded_afterStartSucceeds_doesNotStartAgain() {
        let engine = FakeVoiceActivityAudioEngine()
        let signal = VoiceActivitySignal(engine: engine)

        signal.startIfNeeded()
        signal.startIfNeeded()

        XCTAssertEqual(engine.events, [.installTap, .start])
    }

    func test_deinit_afterStartSucceeds_stopsEngineAndRemovesTap() {
        let engine = FakeVoiceActivityAudioEngine()
        var signal: VoiceActivitySignal? = VoiceActivitySignal(engine: engine)
        signal?.startIfNeeded()

        signal = nil

        XCTAssertEqual(engine.events, [.installTap, .start, .stop, .removeTap])
    }
}

private final class FakeVoiceActivityAudioEngine: VoiceActivityAudioEngine {
    enum Event: Equatable {
        case installTap
        case start
        case stop
        case removeTap
    }

    enum StartError: Error {
        case failed
    }

    private var failuresBeforeSuccess: Int
    private(set) var events: [Event] = []

    init(failuresBeforeSuccess: Int = 0) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    func installTap(bufferHandler: @escaping (AVAudioPCMBuffer) -> Void) {
        events.append(.installTap)
    }

    func start() throws {
        events.append(.start)
        if failuresBeforeSuccess > 0 {
            failuresBeforeSuccess -= 1
            throw StartError.failed
        }
    }

    func stop() {
        events.append(.stop)
    }

    func removeTap() {
        events.append(.removeTap)
    }
}
