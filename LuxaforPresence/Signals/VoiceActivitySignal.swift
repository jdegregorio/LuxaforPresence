import AVFoundation
import Foundation
import OSLog

protocol VoiceActivitySignalProtocol: AnyObject {
    var onQualifyingActivity: ((Date) -> Void)? { get set }
    var isCapturing: Bool { get }
    var authorizationState: MicrophoneAuthorizationState { get }
    func requestAccessIfNeeded()
    func setCaptureContextActive(_ active: Bool)
    func setCaptureContextActive(
        _ active: Bool,
        minimumActiveDuration: TimeInterval
    )
    func isVoiceActive() -> Bool
    var lastVoiceActivityDate: Date? { get }
    func suspend()
    func resume()
    func reset()
}

extension VoiceActivitySignalProtocol {
    func setCaptureContextActive(
        _ active: Bool,
        minimumActiveDuration: TimeInterval
    ) {
        setCaptureContextActive(active)
    }
}

protocol VoiceActivityAudioEngine: AnyObject {
    func installTap(bufferHandler: @escaping (AVAudioPCMBuffer) -> Void)
    func start() throws
    func stop()
    func removeTap()
}

protocol VoiceActivityRetryScheduling {
    func schedule(after delay: TimeInterval, action: @escaping () -> Void)
}

struct MainQueueVoiceActivityRetryScheduler: VoiceActivityRetryScheduling {
    func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
    }
}

final class AVAudioVoiceActivityEngine: VoiceActivityAudioEngine {
    private let engine = AVAudioEngine()

    func installTap(bufferHandler: @escaping (AVAudioPCMBuffer) -> Void) {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            bufferHandler(buffer)
        }
    }

    func start() throws {
        try engine.start()
    }

    func stop() {
        engine.stop()
    }

    func removeTap() {
        engine.inputNode.removeTap(onBus: 0)
    }
}

final class VoiceActivitySignal: VoiceActivitySignalProtocol {
    private enum LifecycleState {
        case stopped
        case starting
        case waitingToRetry
        case started
        case suspended
    }

    private let logger = Logger(
        subsystem: "com.jdegregorio.LuxaforPresence",
        category: "VoiceActivitySignal"
    )
    private let engine: VoiceActivityAudioEngine
    private let retryScheduler: VoiceActivityRetryScheduling
    private let threshold: Double
    private let defaultMinimumActiveDuration: TimeInterval
    private let microphoneActive: () -> Bool
    private let microphoneProbeInterval: TimeInterval
    private let now: () -> Date
    private let maxStartAttempts: Int
    private let retryDelay: TimeInterval
    private let stateLock = NSLock()
    private let sampleLock = NSLock()
    private let lifecycleLock = NSLock()
    private let processingQueue = DispatchQueue(
        label: "com.jdegregorio.LuxaforPresence.voice-processing",
        qos: .utility
    )
    private let processingQueueKey = DispatchSpecificKey<UInt8>()
    private var debouncer: VoiceActivityDebouncer
    private var nextMicrophoneProbeDate: Date?
    private var voiceActive = false
    private var lastActivity: Date?
    private var currentRMS: Double?
    private var activityHandler: ((Date) -> Void)?
    private var lifecycleState = LifecycleState.stopped
    private var authorizationGranted = false
    private var captureContextActive = false
    private var captureMinimumActiveDuration: TimeInterval
    private var acceptingSamples = false
    private var cachedMicrophoneActive = false
    private var resetInProgress = false
    private var pendingResetCount = 0
    private var sampleGeneration: UInt64 = 0

    init(
        threshold: Double = 0.001,
        minimumActiveDuration: TimeInterval = 0.25,
        engine: VoiceActivityAudioEngine = AVAudioVoiceActivityEngine(),
        retryScheduler: VoiceActivityRetryScheduling = MainQueueVoiceActivityRetryScheduler(),
        microphoneActive: @escaping () -> Bool = { false },
        microphoneProbeInterval: TimeInterval = 0.25,
        now: @escaping () -> Date = Date.init,
        maxStartAttempts: Int = 3,
        retryDelay: TimeInterval = 1
    ) {
        let normalizedMinimumActiveDuration = max(0.25, minimumActiveDuration)
        self.engine = engine
        self.retryScheduler = retryScheduler
        self.threshold = threshold
        self.defaultMinimumActiveDuration = normalizedMinimumActiveDuration
        self.microphoneActive = microphoneActive
        self.microphoneProbeInterval = max(0.05, microphoneProbeInterval)
        self.now = now
        self.maxStartAttempts = max(1, maxStartAttempts)
        self.retryDelay = max(0, retryDelay)
        self.debouncer = VoiceActivityDebouncer(
            threshold: threshold,
            minimumActiveDuration: normalizedMinimumActiveDuration
        )
        self.captureMinimumActiveDuration = normalizedMinimumActiveDuration
        processingQueue.setSpecific(key: processingQueueKey, value: 1)
    }

    deinit {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }

        guard lifecycleState == .started else { return }
        setAcceptingSamples(false)
        engine.stop()
        engine.removeTap()
        lifecycleState = .stopped
    }

    var onQualifyingActivity: ((Date) -> Void)? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return activityHandler
        }
        set {
            stateLock.lock()
            activityHandler = newValue
            stateLock.unlock()
        }
    }

    var lastVoiceActivityDate: Date? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return lastActivity
    }

    var isCapturing: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return lifecycleState == .started
    }

    var authorizationState: MicrophoneAuthorizationState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .unknown
        }
    }

    var latestRMS: Double? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentRMS
    }

    func isVoiceActive() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return voiceActive
    }

    func requestAccessIfNeeded() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        logger.log("Microphone authorization state=\(self.authorizationState.rawValue, privacy: .public)")
        switch status {
        case .authorized:
            markAuthorizedAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                if granted {
                    self?.logger.log("Microphone access granted for local voice activity analysis")
                    self?.markAuthorizedAndStart()
                } else {
                    self?.logger.error("Microphone access denied; voice activity analysis disabled")
                }
            }
        case .denied, .restricted:
            logger.error("Microphone access denied or restricted; voice activity analysis disabled")
        @unknown default:
            logger.error("Unknown microphone authorization status \(status.rawValue, privacy: .public)")
        }
    }

    func startIfNeeded() {
        lifecycleLock.lock()
        authorizationGranted = true
        lifecycleLock.unlock()
        setCaptureContextActive(
            true,
            minimumActiveDuration: defaultMinimumActiveDuration
        )
    }

    func setCaptureContextActive(_ active: Bool) {
        setCaptureContextActive(
            active,
            minimumActiveDuration: defaultMinimumActiveDuration
        )
    }

    func setCaptureContextActive(
        _ active: Bool,
        minimumActiveDuration: TimeInterval
    ) {
        let normalizedMinimumActiveDuration = max(0.25, minimumActiveDuration)
        lifecycleLock.lock()
        let contextChanged = captureContextActive != active
        let minimumDurationChanged = captureMinimumActiveDuration
            != normalizedMinimumActiveDuration
        let shouldStart = active
            && authorizationGranted
            && lifecycleState == .stopped
        guard contextChanged || minimumDurationChanged || shouldStart else {
            lifecycleLock.unlock()
            return
        }
        captureContextActive = active
        captureMinimumActiveDuration = normalizedMinimumActiveDuration

        if active {
            lifecycleLock.unlock()
            if contextChanged || minimumDurationChanged {
                prepareForCaptureContext(
                    minimumActiveDuration: normalizedMinimumActiveDuration
                )
            }
            if shouldStart {
                attemptStart(remainingAttempts: maxStartAttempts, from: .stopped)
            }
            logger.debug(
                "Voice activity capture context configured active=true minimumActiveDuration=\(normalizedMinimumActiveDuration, privacy: .public)s"
            )
            return
        }

        let wasStarted = lifecycleState == .started
        if wasStarted {
            setAcceptingSamples(false)
            engine.stop()
            engine.removeTap()
        }
        if lifecycleState != .suspended {
            lifecycleState = .stopped
        }
        lifecycleLock.unlock()
        resetDebounce(preserveLastActivity: true)
        logger.debug("Voice activity capture context became inactive")
    }

    func suspend() {
        lifecycleLock.lock()
        let wasStarted = lifecycleState == .started
        lifecycleState = .suspended
        setAcceptingSamples(false)
        if wasStarted {
            engine.stop()
            engine.removeTap()
        }
        lifecycleLock.unlock()
        resetDebounce(preserveLastActivity: true)
        logger.debug("Voice activity capture suspended")
    }

    func resume() {
        lifecycleLock.lock()
        guard lifecycleState == .suspended else {
            lifecycleLock.unlock()
            return
        }
        lifecycleState = .stopped
        let shouldStart = authorizationGranted && captureContextActive
        lifecycleLock.unlock()

        if shouldStart {
            attemptStart(remainingAttempts: maxStartAttempts, from: .stopped)
        }
        logger.debug("Voice activity capture resumed")
    }

    func reset() {
        resetDebounce(preserveLastActivity: false)
        logger.log("Voice activity timer reset")
    }

    /// Deterministic queue drain used by unit tests for asynchronous audio taps.
    func flushPendingSamplesForTesting() {
        guard DispatchQueue.getSpecific(key: processingQueueKey) == nil else { return }
        processingQueue.sync {}
    }

    private func markAuthorizedAndStart() {
        lifecycleLock.lock()
        authorizationGranted = true
        let shouldStart = captureContextActive && lifecycleState == .stopped
        lifecycleLock.unlock()
        if shouldStart {
            attemptStart(remainingAttempts: maxStartAttempts, from: .stopped)
        }
    }

    private func attemptStart(remainingAttempts: Int, from expectedState: LifecycleState) {
        lifecycleLock.lock()
        guard lifecycleState == expectedState,
              authorizationGranted,
              captureContextActive else {
            lifecycleLock.unlock()
            return
        }
        lifecycleState = .starting
        engine.installTap { [weak self] buffer in
            self?.process(buffer: buffer)
        }

        do {
            try engine.start()
            lifecycleState = .started
            setAcceptingSamples(true)
            lifecycleLock.unlock()
            logger.log("Voice activity engine started")
        } catch {
            setAcceptingSamples(false)
            engine.stop()
            engine.removeTap()
            let shouldRetry = remainingAttempts > 1
            lifecycleState = shouldRetry ? .waitingToRetry : .stopped
            lifecycleLock.unlock()
            logger.error("Failed to start voice activity engine: \(error.localizedDescription, privacy: .public)")

            if shouldRetry {
                retryScheduler.schedule(after: retryDelay) { [weak self] in
                    self?.attemptStart(
                        remainingAttempts: remainingAttempts - 1,
                        from: .waitingToRetry
                    )
                }
            }
        }
    }

    private func process(buffer: AVAudioPCMBuffer) {
        // The render callback must never wait behind lifecycle or microphone
        // discovery work. Dropping one sample at a reset boundary is safer than
        // blocking Zoom's real-time audio path.
        guard sampleLock.try() else { return }
        let shouldAcceptSample = acceptingSamples && !resetInProgress
        let generation = sampleGeneration
        let microphoneActiveAtCapture = cachedMicrophoneActive
        sampleLock.unlock()
        guard shouldAcceptSample else { return }

        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else { return }

        var totalEnergy: Float = 0
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            var sum: Float = 0
            var index = 0
            while index < frameLength {
                let value = samples[index]
                sum += value * value
                index += 1
            }
            totalEnergy += sum
        }

        let meanEnergy = totalEnergy / Float(frameLength * channelCount)
        let sampleDuration: TimeInterval
        if buffer.format.sampleRate.isFinite, buffer.format.sampleRate > 0 {
            sampleDuration = Double(buffer.frameLength) / buffer.format.sampleRate
        } else {
            sampleDuration = 0
        }
        let rms = Double(sqrt(meanEnergy))
        let capturedAt = now()
        processingQueue.async { [weak self] in
            self?.processSample(
                rms: rms,
                duration: sampleDuration,
                at: capturedAt,
                generation: generation,
                microphoneActiveAtCapture: microphoneActiveAtCapture
            )
        }
    }

    private func processSample(
        rms: Double,
        duration: TimeInterval,
        at date: Date,
        generation: UInt64,
        microphoneActiveAtCapture: Bool
    ) {
        sampleLock.lock()
        let shouldProcess = acceptingSamples
            && !resetInProgress
            && generation == sampleGeneration
        sampleLock.unlock()
        guard shouldProcess else { return }

        let rawAboveThreshold = rms.isFinite && rms >= threshold
        var probedMicrophoneActive: Bool?
        if rawAboveThreshold,
           nextMicrophoneProbeDate.map({ date >= $0 }) ?? true {
            let currentMicrophoneActive = microphoneActive()
            nextMicrophoneProbeDate = date.addingTimeInterval(microphoneProbeInterval)
            updateCachedMicrophoneState(
                currentMicrophoneActive,
                generation: generation
            )
            probedMicrophoneActive = currentMicrophoneActive
        }

        let capturedMicrophoneWasActive = microphoneActiveAtCapture
            && (probedMicrophoneActive ?? true)
        var result = debouncer.process(
            rms: rms,
            duration: duration,
            at: date,
            microphoneActiveAtCapture: capturedMicrophoneWasActive
        )

        // Revalidate each would-be event against a fresh off-thread microphone
        // observation. This catches an inactive transition even if the bounded
        // capture-time cache was briefly stale.
        if result.qualifyingActivityDate != nil {
            let currentMicrophoneActive: Bool
            if let probedMicrophoneActive {
                currentMicrophoneActive = probedMicrophoneActive
            } else {
                currentMicrophoneActive = microphoneActive()
                nextMicrophoneProbeDate = date.addingTimeInterval(microphoneProbeInterval)
                updateCachedMicrophoneState(
                    currentMicrophoneActive,
                    generation: generation
                )
            }
            if !currentMicrophoneActive {
                debouncer.reset()
                result = VoiceActivityDebouncer.Result(
                    isCurrentlyAboveThreshold: result.isCurrentlyAboveThreshold,
                    thresholdCrossing: result.thresholdCrossing,
                    qualifyingActivityDate: nil
                )
            }
        }

        // A reset or suspension may have arrived while a bounded microphone
        // query ran. Keep the small publication boundary atomic; the render
        // callback uses try-lock and drops rather than waiting here.
        sampleLock.lock()
        guard acceptingSamples,
              !resetInProgress,
              generation == sampleGeneration else {
            sampleLock.unlock()
            return
        }
        stateLock.lock()
        currentRMS = rms
        voiceActive = result.isCurrentlyAboveThreshold
        if let qualifyingActivityDate = result.qualifyingActivityDate {
            lastActivity = qualifyingActivityDate
        }
        let handler = result.qualifyingActivityDate == nil ? nil : activityHandler
        stateLock.unlock()
        sampleLock.unlock()

        if let crossing = result.thresholdCrossing {
            logger.debug("Voice threshold crossing active=\(crossing, privacy: .public) rms=\(rms, privacy: .public)")
        }
        if let qualifyingActivityDate = result.qualifyingActivityDate {
            logger.debug("Qualifying voice activity at \(qualifyingActivityDate.timeIntervalSinceReferenceDate, privacy: .public) rms=\(rms, privacy: .public)")
            handler?(qualifyingActivityDate)
        }
    }

    private func setAcceptingSamples(_ acceptingSamples: Bool) {
        sampleLock.lock()
        self.acceptingSamples = acceptingSamples
        sampleLock.unlock()
    }

    private func prepareForCaptureContext(minimumActiveDuration: TimeInterval) {
        resetDebounce(
            preserveLastActivity: true,
            minimumActiveDuration: minimumActiveDuration
        )
        sampleLock.lock()
        cachedMicrophoneActive = true
        sampleLock.unlock()
    }

    private func resetDebounce(
        preserveLastActivity: Bool,
        minimumActiveDuration: TimeInterval? = nil
    ) {
        sampleLock.lock()
        sampleGeneration &+= 1
        cachedMicrophoneActive = false
        pendingResetCount += 1
        resetInProgress = true
        sampleLock.unlock()

        let reset = { [self] in
            sampleLock.lock()
            stateLock.lock()
            if let minimumActiveDuration {
                debouncer.reset(minimumActiveDuration: minimumActiveDuration)
            } else {
                debouncer.reset()
            }
            nextMicrophoneProbeDate = nil
            voiceActive = false
            currentRMS = nil
            if !preserveLastActivity {
                lastActivity = nil
            }
            pendingResetCount -= 1
            resetInProgress = pendingResetCount > 0
            stateLock.unlock()
            sampleLock.unlock()
        }
        if DispatchQueue.getSpecific(key: processingQueueKey) != nil {
            reset()
        } else {
            processingQueue.sync(execute: reset)
        }
    }

    private func updateCachedMicrophoneState(
        _ microphoneActive: Bool,
        generation: UInt64
    ) {
        sampleLock.lock()
        if acceptingSamples,
           !resetInProgress,
           generation == sampleGeneration {
            cachedMicrophoneActive = microphoneActive
        }
        sampleLock.unlock()
    }
}
