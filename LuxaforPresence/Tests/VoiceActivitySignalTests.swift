import AVFoundation
import XCTest
@testable import LuxaforPresence

final class VoiceActivitySignalTests: XCTestCase {
    func test_startIfNeeded_afterStartFails_cleansUpAndRetries() {
        let engine = FakeVoiceActivityAudioEngine(failuresBeforeSuccess: 1)
        let scheduler = FakeVoiceActivityRetryScheduler()
        let signal = VoiceActivitySignal(
            engine: engine,
            retryScheduler: scheduler,
            retryDelay: 2
        )

        signal.startIfNeeded()

        XCTAssertEqual(engine.events, [.installTap, .start, .stop, .removeTap])
        XCTAssertEqual(scheduler.scheduledDelays, [2])

        scheduler.runNext()

        XCTAssertEqual(
            engine.events,
            [.installTap, .start, .stop, .removeTap, .installTap, .start]
        )
        XCTAssertFalse(scheduler.hasPendingActions)
    }

    func test_startIfNeeded_whenEveryStartFails_stopsAfterMaximumAttempts() {
        let engine = FakeVoiceActivityAudioEngine(failuresBeforeSuccess: 10)
        let scheduler = FakeVoiceActivityRetryScheduler()
        let signal = VoiceActivitySignal(
            engine: engine,
            retryScheduler: scheduler,
            maxStartAttempts: 3
        )

        signal.startIfNeeded()
        scheduler.runAll()

        XCTAssertEqual(engine.events.filter { $0 == .start }.count, 3)
        XCTAssertEqual(engine.events.filter { $0 == .removeTap }.count, 3)
        XCTAssertEqual(scheduler.scheduledDelays.count, 2)
        XCTAssertFalse(scheduler.hasPendingActions)
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

private final class FakeVoiceActivityRetryScheduler: VoiceActivityRetryScheduling {
    private var pendingActions: [() -> Void] = []
    private(set) var scheduledDelays: [TimeInterval] = []

    var hasPendingActions: Bool {
        !pendingActions.isEmpty
    }

    func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
        scheduledDelays.append(delay)
        pendingActions.append(action)
    }

    func runNext() {
        guard !pendingActions.isEmpty else { return }
        pendingActions.removeFirst()()
    }

    func runAll() {
        while hasPendingActions {
            runNext()
        }
    }
}
