import Foundation
import OSLog

protocol LocalOutputHeartbeating: AnyObject {
    var onHeartbeat: (() -> Void)? { get set }
    func start()
    func stop()
}

/// Optionally provides a bounded recovery guarantee for unobservable USB resets.
///
/// Semantic output changes remain deduplicated. This local-transport-only timer
/// is disabled by default because each forced action requires a fresh connection
/// and the Luxafor desktop listener retains closed sockets for an extended time.
final class LocalOutputHeartbeat: LocalOutputHeartbeating {
    var onHeartbeat: (() -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return heartbeatHandler
        }
        set {
            lock.lock()
            heartbeatHandler = newValue
            lock.unlock()
        }
    }

    private let interval: TimeInterval
    private let timer: LocalServiceRecoveryTimerProtocol
    private let lock = NSLock()
    private let logger = Logger(
        subsystem: "com.jdegregorio.LuxaforPresence",
        category: "LocalOutputHeartbeat"
    )
    private var heartbeatHandler: (() -> Void)?
    private var isRunning = false
    private var generation: UInt64 = 0

    init(
        interval: TimeInterval,
        timer: LocalServiceRecoveryTimerProtocol = LocalServiceRecoveryTimer()
    ) {
        self.interval = max(0.1, interval)
        self.timer = timer
    }

    func start() {
        lock.lock()
        guard !isRunning else {
            lock.unlock()
            return
        }
        generation &+= 1
        let startedGeneration = generation
        isRunning = true
        lock.unlock()
        timer.schedule(every: interval) { [weak self] in
            self?.fire(generation: startedGeneration)
        }
    }

    func stop() {
        lock.lock()
        guard isRunning else {
            lock.unlock()
            return
        }
        generation &+= 1
        isRunning = false
        lock.unlock()
        timer.cancel()
    }

    private func fire(generation: UInt64) {
        lock.lock()
        guard isRunning, self.generation == generation else {
            lock.unlock()
            return
        }
        let handler = heartbeatHandler
        lock.unlock()
        logger.debug("Local output heartbeat requesting physical reassertion")
        handler?()
    }

    deinit {
        stop()
    }
}
