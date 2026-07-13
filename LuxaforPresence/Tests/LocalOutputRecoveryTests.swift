import XCTest
@testable import LuxaforPresence

final class LocalOutputRecoveryTests: XCTestCase {
    func test_recoveryMonitor_reassertsOnlyAfterUnavailableToAvailableEdge() {
        let probe = FakeReachabilityProbe()
        let timer = FakeRecoveryTimer()
        let monitor = LocalServiceRecoveryMonitor(
            probe: probe,
            timer: timer,
            probeInterval: 5
        )
        var reconnectCount = 0
        monitor.onReconnect = { reconnectCount += 1 }

        monitor.start()
        probe.completeNext(reachable: true)
        timer.fire()
        probe.completeNext(reachable: false)
        timer.fire()
        probe.completeNext(reachable: true)

        XCTAssertEqual(reconnectCount, 1)
        XCTAssertEqual(timer.scheduledIntervals, [5])
    }

    func test_recoveryMonitor_startIsIdempotentAndStoppedCompletionIsStale() {
        let probe = FakeReachabilityProbe()
        let timer = FakeRecoveryTimer()
        let monitor = LocalServiceRecoveryMonitor(probe: probe, timer: timer)
        var reconnectCount = 0
        monitor.onReconnect = { reconnectCount += 1 }

        monitor.start()
        monitor.start()
        probe.completeNext(reachable: false)
        timer.fire()
        monitor.stop()
        probe.completeNext(reachable: true)

        XCTAssertEqual(timer.scheduledIntervals.count, 1)
        XCTAssertEqual(timer.cancelCount, 1)
        XCTAssertEqual(reconnectCount, 0)
    }

    func test_recoveryMonitor_ignoresTimerWhileProbeIsPending() {
        let probe = FakeReachabilityProbe()
        let timer = FakeRecoveryTimer()
        let monitor = LocalServiceRecoveryMonitor(probe: probe, timer: timer)

        monitor.start()
        timer.fire()
        timer.fire()

        XCTAssertEqual(probe.pendingCount, 1)
    }

    func test_heartbeat_startIsIdempotentAndStopRejectsQueuedHandler() {
        let timer = FakeRecoveryTimer()
        let heartbeat = LocalOutputHeartbeat(interval: 30, timer: timer)
        var heartbeatCount = 0
        heartbeat.onHeartbeat = { heartbeatCount += 1 }

        heartbeat.start()
        heartbeat.start()
        let staleHandler = timer.handler
        timer.fire()
        heartbeat.stop()
        staleHandler?()

        XCTAssertEqual(timer.scheduledIntervals, [30])
        XCTAssertEqual(timer.cancelCount, 1)
        XCTAssertEqual(heartbeatCount, 1)
    }

    func test_heartbeat_clampsNonPositiveDirectInterval() {
        let timer = FakeRecoveryTimer()
        let heartbeat = LocalOutputHeartbeat(interval: -1, timer: timer)

        heartbeat.start()

        XCTAssertEqual(timer.scheduledIntervals, [0.1])
    }

    func test_recoveryComponents_areLocalTransportOnly() {
        let localConfig = PresenceEngine.Config(values: [:])
        let remoteConfig = PresenceEngine.Config(values: [
            "transportMode": "remote",
            "remoteWebhookUserId": "valid-user",
        ])

        XCTAssertNotNil(localConfig.makeLocalServiceRecoveryMonitor())
        XCTAssertNotNil(localConfig.makeLocalOutputHeartbeat())
        XCTAssertNil(remoteConfig.makeLocalServiceRecoveryMonitor())
        XCTAssertNil(remoteConfig.makeLocalOutputHeartbeat())
    }
}

private final class FakeReachabilityProbe: LocalServiceReachabilityProbing {
    private var completions: [(Bool) -> Void] = []

    var pendingCount: Int { completions.count }

    func probe(completion: @escaping (Bool) -> Void) {
        completions.append(completion)
    }

    func completeNext(reachable: Bool) {
        guard !completions.isEmpty else {
            XCTFail("No reachability probe is pending")
            return
        }
        completions.removeFirst()(reachable)
    }
}

private final class FakeRecoveryTimer: LocalServiceRecoveryTimerProtocol {
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
