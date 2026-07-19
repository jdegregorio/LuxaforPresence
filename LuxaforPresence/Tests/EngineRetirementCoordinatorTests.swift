import XCTest
@testable import LuxaforPresence

final class EngineRetirementCoordinatorTests: XCTestCase {
    func test_retireBlockingAudioEngine_keepsMainQueueResponsive() {
        let engine = BlockingRetiringEngine()
        let coordinator = EngineRetirementCoordinator()
        let completion = expectation(description: "retirement completed")
        let mainQueueTurn = expectation(description: "main queue remained responsive")
        var completionWasOnMain = false

        let startedAt = Date()
        coordinator.retire(engine, action: .suspend) {
            completionWasOnMain = Thread.isMainThread
            completion.fulfill()
        }
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.1)
        XCTAssertEqual(engine.waitUntilStarted(), .success)

        DispatchQueue.main.async {
            mainQueueTurn.fulfill()
        }
        wait(for: [mainQueueTurn], timeout: 1)
        engine.release()
        wait(for: [completion], timeout: 1)

        XCTAssertTrue(completionWasOnMain)
        XCTAssertEqual(engine.suspendCount, 1)
        XCTAssertEqual(engine.shutdownCount, 0)
    }

    func test_retireChangedDestination_shutsDownOldEngine() {
        let engine = RecordingRetiringEngine()
        let coordinator = EngineRetirementCoordinator()
        let completion = expectation(description: "retirement completed")

        coordinator.retire(engine, action: .shutdown) {
            completion.fulfill()
        }

        wait(for: [completion], timeout: 1)
        XCTAssertEqual(engine.suspendCount, 0)
        XCTAssertEqual(engine.shutdownCount, 1)
    }
}

private final class RecordingRetiringEngine: PresenceEngineOutputRetiring {
    private(set) var suspendCount = 0
    private(set) var shutdownCount = 0

    func suspendOutput() {
        suspendCount += 1
    }

    func shutdownOutput() {
        shutdownCount += 1
    }
}

private final class BlockingRetiringEngine: PresenceEngineOutputRetiring {
    private let started = DispatchSemaphore(value: 0)
    private let releaseSignal = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var storedSuspendCount = 0
    private var storedShutdownCount = 0

    var suspendCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedSuspendCount
    }

    var shutdownCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedShutdownCount
    }

    func suspendOutput() {
        lock.lock()
        storedSuspendCount += 1
        lock.unlock()
        started.signal()
        _ = releaseSignal.wait(timeout: .now() + 1)
    }

    func shutdownOutput() {
        lock.lock()
        storedShutdownCount += 1
        lock.unlock()
    }

    func waitUntilStarted() -> DispatchTimeoutResult {
        started.wait(timeout: .now() + 1)
    }

    func release() {
        releaseSignal.signal()
    }
}
