import XCTest
@testable import LuxaforPresence

final class GoogleMeetDetectorTests: XCTestCase {
    func testIsMeetingActive_executesAppleScriptOnMainThread() {
        let scriptExecuted = expectation(description: "AppleScript executed")
        let detectionCompleted = expectation(description: "detection completed")
        let detector = GoogleMeetDetector(
            browserRunning: { true },
            appleScriptExecutor: { _ in
                XCTAssertTrue(Thread.isMainThread)
                scriptExecuted.fulfill()
                return true
            }
        )

        DispatchQueue.global(qos: .utility).async {
            _ = detector.isMeetingActive()
            detectionCompleted.fulfill()
        }

        wait(for: [scriptExecuted, detectionCompleted], timeout: 2)
    }
}
