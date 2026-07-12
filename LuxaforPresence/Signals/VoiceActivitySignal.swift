import AVFoundation
import Foundation
import OSLog

protocol VoiceActivitySignalProtocol {
    func requestAccessIfNeeded()
    func isVoiceActive() -> Bool
    var lastVoiceActivityDate: Date? { get }
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
    }

    private let logger = Logger(subsystem: "com.example.LuxaforPresence", category: "VoiceActivitySignal")
    private let engine: VoiceActivityAudioEngine
    private let retryScheduler: VoiceActivityRetryScheduling
    private let threshold: Double
    private let maxStartAttempts: Int
    private let retryDelay: TimeInterval
    private let stateLock = NSLock()
    private let lifecycleLock = NSLock()
    private var voiceActive = false
    private var lastActivity: Date?
    private var lifecycleState = LifecycleState.stopped

    init(
        threshold: Double = 0.02,
        engine: VoiceActivityAudioEngine = AVAudioVoiceActivityEngine(),
        retryScheduler: VoiceActivityRetryScheduling = MainQueueVoiceActivityRetryScheduler(),
        maxStartAttempts: Int = 3,
        retryDelay: TimeInterval = 1
    ) {
        self.threshold = threshold
        self.engine = engine
        self.retryScheduler = retryScheduler
        self.maxStartAttempts = max(1, maxStartAttempts)
        self.retryDelay = max(0, retryDelay)
    }

    deinit {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }

        guard lifecycleState == .started else { return }
        engine.stop()
        engine.removeTap()
        lifecycleState = .stopped
    }

    var lastVoiceActivityDate: Date? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return lastActivity
    }

    func isVoiceActive() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return voiceActive
    }

    func requestAccessIfNeeded() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            startIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                if granted {
                    self?.logger.log("Microphone access granted for VAD")
                    self?.startIfNeeded()
                } else {
                    self?.logger.error("Microphone access denied; VAD disabled")
                }
            }
        case .denied, .restricted:
            logger.error("Microphone access denied or restricted; VAD disabled")
        @unknown default:
            logger.error("Unknown microphone authorization status \(status.rawValue, privacy: .public)")
        }
    }

    func startIfNeeded() {
        attemptStart(remainingAttempts: maxStartAttempts, from: .stopped)
    }

    private func attemptStart(remainingAttempts: Int, from expectedState: LifecycleState) {
        lifecycleLock.lock()
        guard lifecycleState == expectedState else {
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
            lifecycleLock.unlock()
            logger.log("Voice activity engine started")
        } catch {
            engine.stop()
            engine.removeTap()
            let shouldRetry = remainingAttempts > 1
            lifecycleState = shouldRetry ? .waitingToRetry : .stopped
            lifecycleLock.unlock()
            logger.error("Failed to start VAD engine: \(error.localizedDescription, privacy: .public)")

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
        let rms = sqrt(meanEnergy)
        let isActive = Double(rms) >= threshold
        let now = Date()

        stateLock.lock()
        voiceActive = isActive
        if isActive {
            lastActivity = now
        }
        stateLock.unlock()
    }
}
