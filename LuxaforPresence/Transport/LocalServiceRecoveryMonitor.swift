import Foundation
import Network
import OSLog

protocol LocalServiceRecoveryMonitoring: AnyObject {
    var onReconnect: (() -> Void)? { get set }
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

/// A neutral TCP probe for the configured local webhook listener.
///
/// Luxafor documents the listener address but no health endpoint. Opening and
/// immediately closing a TCP connection observes listener lifecycle without
/// sending a color or depending on an undocumented desktop-app bundle ID.
final class LocalServiceTCPProbe: LocalServiceReachabilityProbing {
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(
        label: "com.jdegregorio.LuxaforPresence.local-service-probe",
        qos: .utility
    )
    private let timeout: TimeInterval

    init(endpoint: LocalWebhookEndpoint, timeout: TimeInterval = 1) {
        host = NWEndpoint.Host(endpoint.baseURL.host ?? "127.0.0.1")
        let defaultPort = endpoint.baseURL.scheme?.lowercased() == "https" ? 443 : 80
        port = NWEndpoint.Port(
            rawValue: UInt16(endpoint.baseURL.port ?? defaultPort)
        ) ?? NWEndpoint.Port(rawValue: 5383)!
        self.timeout = max(0.1, timeout)
    }

    func probe(completion: @escaping (Bool) -> Void) {
        let connection = NWConnection(host: host, port: port, using: .tcp)
        var completed = false
        let finish: (Bool) -> Void = { reachable in
            guard !completed else { return }
            completed = true
            connection.stateUpdateHandler = nil
            connection.cancel()
            completion(reachable)
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                finish(true)
            case .failed, .cancelled:
                finish(false)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout) {
            finish(false)
        }
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

    private let probe: LocalServiceReachabilityProbing
    private let timer: LocalServiceRecoveryTimerProtocol
    private let probeInterval: TimeInterval
    private let lock = NSLock()
    private let logger = Logger(
        subsystem: "com.jdegregorio.LuxaforPresence",
        category: "LocalServiceRecovery"
    )
    private var reconnectHandler: (() -> Void)?
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
        lock.unlock()

        if previousReachability != reachable {
            logger.log("Local webhook reachability changed reachable=\(reachable, privacy: .public)")
        }
        if handler != nil {
            logger.log("Local webhook listener recovered; requesting output reassertion")
        }
        handler?()
    }
}
