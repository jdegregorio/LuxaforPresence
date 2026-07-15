import Foundation
import OSLog

protocol LocalServiceRecoveryMonitoring: AnyObject {
    var onReconnect: (() -> Void)? { get set }
    var onReachabilityChange: ((Bool) -> Void)? { get set }
    func start()
    func stop()
}

protocol LocalServiceReachabilityProbing {
    func probe(completion: @escaping (Bool) -> Void)
}

protocol LocalServiceRecoveryTimerProtocol: AnyObject {
    func schedule(every interval: TimeInterval, handler: @escaping () -> Void)
    func cancel()
}

final class LocalServiceRecoveryTimer: LocalServiceRecoveryTimerProtocol {
    private let queue = DispatchQueue(
        label: "com.jdegregorio.LuxaforPresence.local-service-recovery",
        qos: .utility
    )
    private var timer: DispatchSourceTimer?

    func schedule(every interval: TimeInterval, handler: @escaping () -> Void) {
        cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler(handler: handler)
        self.timer = timer
        timer.resume()
    }

    func cancel() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }

    deinit {
        cancel()
    }
}

/// A persistent HTTP probe for the configured local webhook listener.
///
/// A HEAD request checks the documented color endpoint without changing the
/// device. Reusing one URLSession connection is important because the Luxafor
/// desktop listener retains disconnected sockets for an extended period.
final class LocalServiceHTTPProbe: LocalServiceReachabilityProbing {
    private let colorURL: URL
    private let session: URLSession
    private let timeout: TimeInterval

    init(
        endpoint: LocalWebhookEndpoint,
        timeout: TimeInterval = 1,
        session: URLSession = LocalWebhookSession.make()
    ) {
        colorURL = endpoint.colorURL
        self.timeout = max(0.1, timeout)
        self.session = session
    }

    func probe(completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: colorURL, timeoutInterval: timeout)
        request.httpMethod = "HEAD"
        request.addValue("keep-alive", forHTTPHeaderField: "Connection")
        session.dataTask(with: request) { _, response, error in
            completion(error == nil && response is HTTPURLResponse)
        }.resume()
    }
}

/// Reasserts output only after an observed listener outage has recovered.
final class LocalServiceRecoveryMonitor: LocalServiceRecoveryMonitoring {
    static let defaultProbeInterval: TimeInterval = 5

    var onReconnect: (() -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return reconnectHandler
        }
        set {
            lock.lock()
            reconnectHandler = newValue
            lock.unlock()
        }
    }

    var onReachabilityChange: ((Bool) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return reachabilityChangeHandler
        }
        set {
            lock.lock()
            reachabilityChangeHandler = newValue
            lock.unlock()
        }
    }

    private let probe: LocalServiceReachabilityProbing
    private let timer: LocalServiceRecoveryTimerProtocol
    private let probeInterval: TimeInterval
    private let lock = NSLock()
    private let logger = Logger(
        subsystem: "com.jdegregorio.LuxaforPresence",
        category: "LocalServiceRecovery"
    )
    private var reconnectHandler: (() -> Void)?
    private var reachabilityChangeHandler: ((Bool) -> Void)?
    private var isRunning = false
    private var probeInFlight = false
    private var generation: UInt64 = 0
    private var lastReachability: Bool?

    init(
        probe: LocalServiceReachabilityProbing,
        timer: LocalServiceRecoveryTimerProtocol = LocalServiceRecoveryTimer(),
        probeInterval: TimeInterval = defaultProbeInterval
    ) {
        self.probe = probe
        self.timer = timer
        self.probeInterval = max(0.25, probeInterval)
    }

    func start() {
        lock.lock()
        guard !isRunning else {
            lock.unlock()
            return
        }
        generation &+= 1
        isRunning = true
        probeInFlight = false
        lastReachability = nil
        lock.unlock()

        probeIfNeeded()
        timer.schedule(every: probeInterval) { [weak self] in
            self?.probeIfNeeded()
        }
        logger.debug("Local webhook recovery monitor started")
    }

    func stop() {
        lock.lock()
        guard isRunning else {
            lock.unlock()
            return
        }
        generation &+= 1
        isRunning = false
        probeInFlight = false
        lastReachability = nil
        lock.unlock()
        timer.cancel()
        logger.debug("Local webhook recovery monitor stopped")
    }

    private func probeIfNeeded() {
        lock.lock()
        guard isRunning, !probeInFlight else {
            lock.unlock()
            return
        }
        probeInFlight = true
        let requestedGeneration = generation
        lock.unlock()

        probe.probe { [weak self] reachable in
            self?.finishProbe(reachable: reachable, generation: requestedGeneration)
        }
    }

    private func finishProbe(reachable: Bool, generation: UInt64) {
        lock.lock()
        guard isRunning, self.generation == generation else {
            lock.unlock()
            return
        }
        probeInFlight = false
        let previousReachability = lastReachability
        lastReachability = reachable
        let handler = previousReachability == false && reachable
            ? reconnectHandler
            : nil
        let reachabilityHandler = previousReachability != reachable
            ? reachabilityChangeHandler
            : nil
        lock.unlock()

        if previousReachability != reachable {
            logger.log("Local webhook reachability changed reachable=\(reachable, privacy: .public)")
        }
        if handler != nil {
            logger.log("Local webhook listener recovered; requesting output reassertion")
        }
        reachabilityHandler?(reachable)
        handler?()
    }
}
