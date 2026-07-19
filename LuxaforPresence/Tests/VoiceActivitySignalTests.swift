import AVFoundation
import XCTest
@testable import LuxaforPresence

final class VoiceActivitySignalTests: XCTestCase {
    func test_debouncer_isolatedSubMinimumSignal_doesNotQualify() {
        var debouncer = VoiceActivityDebouncer(
            threshold: 0.02,
            minimumActiveDuration: 0.25
        )
        let date = Date(timeIntervalSinceReferenceDate: 1_000)

        let result = debouncer.process(
            rms: 0.1,
            duration: 0.2,
            at: date,
            microphoneActiveAtCapture: true
        )

        XCTAssertTrue(result.isCurrentlyAboveThreshold)
        XCTAssertNil(result.qualifyingActivityDate)
    }

    func test_debouncer_cumulativeConsecutiveSignal_qualifiesAt250Milliseconds() {
        var debouncer = VoiceActivityDebouncer(
            threshold: 0.02,
            minimumActiveDuration: 0.25
        )
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        var result: VoiceActivityDebouncer.Result?

        for index in 0..<5 {
            result = debouncer.process(
                rms: 0.1,
                duration: 0.05,
                at: date.addingTimeInterval(Double(index) * 0.05),
                microphoneActiveAtCapture: true
            )
        }

        XCTAssertEqual(
            result?.qualifyingActivityDate,
            date.addingTimeInterval(0.2)
        )
    }

    func test_debouncer_gapResetsPartialEvidence() {
        var debouncer = VoiceActivityDebouncer(
            threshold: 0.02,
            minimumActiveDuration: 0.25
        )
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        _ = debouncer.process(
            rms: 0.1,
            duration: 0.15,
            at: date,
            microphoneActiveAtCapture: true
        )
        _ = debouncer.process(
            rms: 0,
            duration: 0.01,
            at: date.addingTimeInterval(0.15),
            microphoneActiveAtCapture: true
        )

        let result = debouncer.process(
            rms: 0.1,
            duration: 0.15,
            at: date.addingTimeInterval(0.16),
            microphoneActiveAtCapture: true
        )

        XCTAssertNil(result.qualifyingActivityDate)
    }

    func test_debouncer_microphoneInactive_resetsPartialEvidence() {
        var debouncer = VoiceActivityDebouncer(
            threshold: 0.02,
            minimumActiveDuration: 0.25
        )
        let date = Date(timeIntervalSinceReferenceDate: 1_000)

        _ = debouncer.process(
            rms: 0.1,
            duration: 0.2,
            at: date,
            microphoneActiveAtCapture: true
        )
        let inactiveResult = debouncer.process(
            rms: 0.1,
            duration: 0.05,
            at: date.addingTimeInterval(0.2),
            microphoneActiveAtCapture: false
        )
        let activeResult = debouncer.process(
            rms: 0.1,
            duration: 0.05,
            at: date.addingTimeInterval(0.25),
            microphoneActiveAtCapture: true
        )

        XCTAssertNil(inactiveResult.qualifyingActivityDate)
        XCTAssertNil(activeResult.qualifyingActivityDate)
    }

    func test_debouncer_microphoneBecomesActive_doesNotReuseEarlierNoise() {
        var debouncer = VoiceActivityDebouncer(
            threshold: 0.02,
            minimumActiveDuration: 0.25
        )
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        let initialNoise = debouncer.process(
            rms: 0.1,
            duration: 0.2,
            at: date,
            microphoneActiveAtCapture: false
        )
        let firstActiveSample = debouncer.process(
            rms: 0.1,
            duration: 0.05,
            at: date.addingTimeInterval(0.2),
            microphoneActiveAtCapture: true
        )
        let secondActiveSample = debouncer.process(
            rms: 0.1,
            duration: 0.05,
            at: date.addingTimeInterval(0.25),
            microphoneActiveAtCapture: true
        )
        let qualifyingSample = debouncer.process(
            rms: 0.1,
            duration: 0.2,
            at: date.addingTimeInterval(0.3),
            microphoneActiveAtCapture: true
        )

        XCTAssertNil(initialNoise.qualifyingActivityDate)
        XCTAssertNil(firstActiveSample.qualifyingActivityDate)
        XCTAssertNil(secondActiveSample.qualifyingActivityDate)
        XCTAssertEqual(
            qualifyingSample.qualifyingActivityDate,
            date.addingTimeInterval(0.3)
        )
    }

    func test_debouncer_continuousActivity_refreshesAtMostOncePerSecond() {
        var debouncer = VoiceActivityDebouncer(
            threshold: 0.02,
            minimumActiveDuration: 0.25
        )
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        var qualifyingDates: [Date] = []

        for index in 0...6 {
            let result = debouncer.process(
                rms: 0.1,
                duration: 0.25,
                at: date.addingTimeInterval(Double(index) * 0.25),
                microphoneActiveAtCapture: true
            )
            if let qualifyingDate = result.qualifyingActivityDate {
                qualifyingDates.append(qualifyingDate)
            }
        }

        XCTAssertEqual(
            qualifyingDates,
            [date, date.addingTimeInterval(1)]
        )
    }

    func test_debouncer_sparseEvidenceOutsideOneSecondWindow_doesNotQualify() {
        var debouncer = VoiceActivityDebouncer(
            threshold: 0.02,
            minimumActiveDuration: 0.25
        )
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        _ = debouncer.process(
            rms: 0.1,
            duration: 0.15,
            at: date,
            microphoneActiveAtCapture: true
        )

        let result = debouncer.process(
            rms: 0.1,
            duration: 0.1,
            at: date.addingTimeInterval(1.001),
            microphoneActiveAtCapture: true
        )

        XCTAssertNil(result.qualifyingActivityDate)
    }

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

    func test_captureContextBeforeAuthorization_waitsToStart() {
        let engine = FakeVoiceActivityAudioEngine()
        let signal = VoiceActivitySignal(engine: engine)

        signal.setCaptureContextActive(true)

        XCTAssertFalse(signal.isCapturing)
        XCTAssertTrue(engine.events.isEmpty)

        signal.startIfNeeded()

        XCTAssertTrue(signal.isCapturing)
        XCTAssertEqual(engine.events, [.installTap, .start])
    }

    func test_captureContextEnding_stopsAndRemovesTapUntilContextReturns() {
        let engine = FakeVoiceActivityAudioEngine()
        let signal = VoiceActivitySignal(engine: engine)
        signal.startIfNeeded()

        signal.setCaptureContextActive(false)
        signal.setCaptureContextActive(false)

        XCTAssertFalse(signal.isCapturing)
        XCTAssertEqual(
            engine.events,
            [.installTap, .start, .stop, .removeTap]
        )

        signal.setCaptureContextActive(true)

        XCTAssertTrue(signal.isCapturing)
        XCTAssertEqual(
            engine.events,
            [.installTap, .start, .stop, .removeTap, .installTap, .start]
        )
    }

    func test_captureContextEnding_cancelsPendingStartRetry() {
        let engine = FakeVoiceActivityAudioEngine(failuresBeforeSuccess: 1)
        let scheduler = FakeVoiceActivityRetryScheduler()
        let signal = VoiceActivitySignal(
            engine: engine,
            retryScheduler: scheduler
        )
        signal.startIfNeeded()

        signal.setCaptureContextActive(false)
        scheduler.runAll()

        XCTAssertFalse(signal.isCapturing)
        XCTAssertEqual(engine.events, [.installTap, .start, .stop, .removeTap])
    }

    func test_contextEndsWhileSuspended_resumeDoesNotRestartCapture() {
        let engine = FakeVoiceActivityAudioEngine()
        let signal = VoiceActivitySignal(engine: engine)
        signal.startIfNeeded()
        signal.suspend()

        signal.setCaptureContextActive(false)
        signal.resume()

        XCTAssertFalse(signal.isCapturing)
        XCTAssertEqual(
            engine.events,
            [.installTap, .start, .stop, .removeTap]
        )
    }

    func test_captureContextBoundary_discardsPartialVoiceEvidence() throws {
        let engine = FakeVoiceActivityAudioEngine()
        let signal = VoiceActivitySignal(
            threshold: 0.02,
            minimumActiveDuration: 0.25,
            engine: engine,
            microphoneActive: { true }
        )
        signal.startIfNeeded()
        engine.deliver(try makeBuffer(rms: 0.1, duration: 0.2))
        signal.flushPendingSamplesForTesting()

        signal.setCaptureContextActive(false)
        signal.setCaptureContextActive(true)
        engine.deliver(try makeBuffer(rms: 0.1, duration: 0.1))
        signal.flushPendingSamplesForTesting()

        XCTAssertNil(signal.lastVoiceActivityDate)
    }

    func test_zoomQualification_requiresThreeSecondsOfContinuousSignal() throws {
        let engine = FakeVoiceActivityAudioEngine()
        var currentDate = Date(timeIntervalSinceReferenceDate: 1_500)
        let signal = VoiceActivitySignal(
            threshold: 0.02,
            minimumActiveDuration: 0.25,
            engine: engine,
            microphoneActive: { true },
            now: { currentDate }
        )
        signal.startIfNeeded()
        signal.setCaptureContextActive(
            true,
            minimumActiveDuration: PresenceEngine.minimumZoomSignalDuration
        )

        for _ in 0..<11 {
            engine.deliver(try makeBuffer(rms: 0.1, duration: 0.25))
            signal.flushPendingSamplesForTesting()
            currentDate = currentDate.addingTimeInterval(0.25)
        }
        XCTAssertNil(signal.lastVoiceActivityDate)

        let qualifyingEvent = expectation(description: "three-second signal qualifies")
        signal.onQualifyingActivity = { _ in qualifyingEvent.fulfill() }
        engine.deliver(try makeBuffer(rms: 0.1, duration: 0.25))
        signal.flushPendingSamplesForTesting()

        wait(for: [qualifyingEvent], timeout: 1)
        XCTAssertEqual(signal.lastVoiceActivityDate, currentDate)
    }

    func test_changingQualificationDuration_discardsEarlierPartialEvidence() throws {
        let engine = FakeVoiceActivityAudioEngine()
        let signal = VoiceActivitySignal(
            threshold: 0.02,
            minimumActiveDuration: 0.25,
            engine: engine,
            microphoneActive: { true }
        )
        signal.startIfNeeded()
        engine.deliver(try makeBuffer(rms: 0.1, duration: 0.2))
        signal.flushPendingSamplesForTesting()

        signal.setCaptureContextActive(true, minimumActiveDuration: 3)
        engine.deliver(try makeBuffer(rms: 0.1, duration: 0.1))
        signal.flushPendingSamplesForTesting()

        XCTAssertNil(signal.lastVoiceActivityDate)
    }

    func test_deinit_afterStartSucceeds_stopsEngineAndRemovesTap() {
        let engine = FakeVoiceActivityAudioEngine()
        var signal: VoiceActivitySignal? = VoiceActivitySignal(engine: engine)
        signal?.startIfNeeded()

        signal = nil

        XCTAssertEqual(engine.events, [.installTap, .start, .stop, .removeTap])
    }

    func test_suspendAndResume_restartsCaptureAndInvalidatesPartialBurst() throws {
        let engine = FakeVoiceActivityAudioEngine()
        let signal = VoiceActivitySignal(
            threshold: 0.02,
            minimumActiveDuration: 0.25,
            engine: engine,
            microphoneActive: { true }
        )
        let qualifyingEvent = expectation(description: "qualifying event")
        signal.onQualifyingActivity = { _ in qualifyingEvent.fulfill() }
        signal.startIfNeeded()

        engine.deliver(try makeBuffer(rms: 0.1, duration: 0.01))
        signal.flushPendingSamplesForTesting()
        engine.deliver(try makeBuffer(rms: 0.1, duration: 0.15))
        signal.flushPendingSamplesForTesting()
        signal.suspend()
        signal.resume()
        engine.deliver(try makeBuffer(rms: 0.1, duration: 0.01))
        signal.flushPendingSamplesForTesting()
        engine.deliver(try makeBuffer(rms: 0.1, duration: 0.15))
        signal.flushPendingSamplesForTesting()
        engine.deliver(try makeBuffer(rms: 0.1, duration: 0.1))
        signal.flushPendingSamplesForTesting()

        wait(for: [qualifyingEvent], timeout: 2)
        XCTAssertEqual(
            engine.events,
            [.installTap, .start, .stop, .removeTap, .installTap, .start]
        )
    }

    func test_signal_activeCaptureContext_countsFirstAudioBuffer() throws {
        let engine = FakeVoiceActivityAudioEngine()
        var currentDate = Date(timeIntervalSinceReferenceDate: 2_000)
        let signal = VoiceActivitySignal(
            threshold: 0.02,
            minimumActiveDuration: 0.25,
            engine: engine,
            microphoneActive: { true },
            now: { currentDate }
        )
        signal.startIfNeeded()

        let qualifyingEvent = expectation(description: "active-context voice qualifies")
        signal.onQualifyingActivity = { _ in qualifyingEvent.fulfill() }
        engine.deliver(try makeBuffer(rms: 0.1, duration: 0.2))
        signal.flushPendingSamplesForTesting()
        XCTAssertNil(signal.lastVoiceActivityDate)

        currentDate = currentDate.addingTimeInterval(0.05)
        engine.deliver(try makeBuffer(rms: 0.1, duration: 0.05))
        signal.flushPendingSamplesForTesting()

        wait(for: [qualifyingEvent], timeout: 2)
        XCTAssertEqual(signal.lastVoiceActivityDate, currentDate)
    }

    func test_signal_reset_discardsPartialEvidence() throws {
        let engine = FakeVoiceActivityAudioEngine()
        let signal = VoiceActivitySignal(
            threshold: 0.02,
            minimumActiveDuration: 0.25,
            engine: engine,
            microphoneActive: { true }
        )
        signal.startIfNeeded()
        engine.deliver(try makeBuffer(rms: 0.1, duration: 0.01))
        signal.flushPendingSamplesForTesting()
        engine.deliver(try makeBuffer(rms: 0.1, duration: 0.15))
        signal.flushPendingSamplesForTesting()

        signal.reset()
        engine.deliver(try makeBuffer(rms: 0.1, duration: 0.1))
        signal.flushPendingSamplesForTesting()
        engine.deliver(try makeBuffer(rms: 0.1, duration: 0.1))
        signal.flushPendingSamplesForTesting()

        XCTAssertNil(signal.lastVoiceActivityDate)

        let qualifyingEvent = expectation(description: "fresh post-reset evidence qualifies")
        signal.onQualifyingActivity = { _ in qualifyingEvent.fulfill() }
        engine.deliver(try makeBuffer(rms: 0.1, duration: 0.15))
        signal.flushPendingSamplesForTesting()

        wait(for: [qualifyingEvent], timeout: 2)
    }

    func test_signal_resetDuringBlockedProbe_discardsInFlightQualification() throws {
        let engine = FakeVoiceActivityAudioEngine()
        var currentDate = Date(timeIntervalSinceReferenceDate: 2_500)
        let probeEntered = DispatchSemaphore(value: 0)
        let releaseProbe = DispatchSemaphore(value: 0)
        var probeCount = 0
        let signal = VoiceActivitySignal(
            threshold: 0.02,
            minimumActiveDuration: 0.25,
            engine: engine,
            microphoneActive: {
                probeCount += 1
                if probeCount == 2 {
                    probeEntered.signal()
                    _ = releaseProbe.wait(timeout: .now() + 2)
                }
                return true
            },
            microphoneProbeInterval: 0.05,
            now: { currentDate }
        )
        let staleQualification = expectation(description: "pre-reset event is discarded")
        staleQualification.isInverted = true
        signal.onQualifyingActivity = { _ in staleQualification.fulfill() }
        signal.startIfNeeded()
        engine.deliver(try makeBuffer(rms: 0.1, duration: 0.01))
        signal.flushPendingSamplesForTesting()
        engine.deliver(try makeBuffer(rms: 0.1, duration: 0.15))
        signal.flushPendingSamplesForTesting()

        currentDate = currentDate.addingTimeInterval(0.1)
        engine.deliver(try makeBuffer(rms: 0.1, duration: 0.1))
        XCTAssertEqual(probeEntered.wait(timeout: .now() + 1), .success)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) {
            releaseProbe.signal()
        }

        signal.reset()

        wait(for: [staleQualification], timeout: 0.1)
        XCTAssertNil(signal.lastVoiceActivityDate)
    }

    func test_signal_thresholdChatter_boundsMicrophoneDiscovery() throws {
        let engine = FakeVoiceActivityAudioEngine()
        var currentDate = Date(timeIntervalSinceReferenceDate: 3_000)
        var probeCount = 0
        let signal = VoiceActivitySignal(
            engine: engine,
            microphoneActive: {
                probeCount += 1
                return false
            },
            microphoneProbeInterval: 0.25,
            now: { currentDate }
        )
        signal.startIfNeeded()

        for index in 0..<20 {
            currentDate = Date(timeIntervalSinceReferenceDate: 3_000 + Double(index) * 0.01)
            let rms: Float = index.isMultiple(of: 2) ? 0.1 : 0
            engine.deliver(try makeBuffer(rms: rms, duration: 0.01))
            signal.flushPendingSamplesForTesting()
        }
        currentDate = Date(timeIntervalSinceReferenceDate: 3_000.26)
        engine.deliver(try makeBuffer(rms: 0.1, duration: 0.01))
        signal.flushPendingSamplesForTesting()

        XCTAssertEqual(probeCount, 2)
    }

    func test_signal_blockedMicrophoneProbe_doesNotBlockAudioCallback() throws {
        let engine = FakeVoiceActivityAudioEngine()
        let probeEntered = DispatchSemaphore(value: 0)
        let releaseProbe = DispatchSemaphore(value: 0)
        let probeFinished = expectation(description: "microphone probe finished")
        let signal = VoiceActivitySignal(
            engine: engine,
            microphoneActive: {
                probeEntered.signal()
                _ = releaseProbe.wait(timeout: .now() + 2)
                probeFinished.fulfill()
                return false
            }
        )
        signal.startIfNeeded()
        engine.deliver(try makeBuffer(rms: 0.1, duration: 0.01))
        XCTAssertEqual(probeEntered.wait(timeout: .now() + 1), .success)

        let startedAt = Date()
        for _ in 0..<20 {
            engine.deliver(try makeBuffer(rms: 0.1, duration: 0.01))
        }
        let deliveryDuration = Date().timeIntervalSince(startedAt)
        releaseProbe.signal()

        wait(for: [probeFinished], timeout: 2)
        XCTAssertTrue(deliveryDuration < 0.5)
    }

    private func makeBuffer(
        rms: Float,
        duration: TimeInterval
    ) throws -> AVAudioPCMBuffer {
        let sampleRate = 1_000.0
        let format = try XCTUnwrap(
            AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 1
            )
        )
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        )
        buffer.frameLength = frameCount
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<Int(frameCount) {
            samples[index] = rms
        }
        return buffer
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
    private var bufferHandler: ((AVAudioPCMBuffer) -> Void)?

    init(failuresBeforeSuccess: Int = 0) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    func installTap(bufferHandler: @escaping (AVAudioPCMBuffer) -> Void) {
        events.append(.installTap)
        self.bufferHandler = bufferHandler
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
        bufferHandler = nil
    }

    func deliver(_ buffer: AVAudioPCMBuffer) {
        bufferHandler?(buffer)
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
