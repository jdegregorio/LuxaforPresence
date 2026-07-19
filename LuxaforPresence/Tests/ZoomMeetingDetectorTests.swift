import Darwin
import XCTest
@testable import LuxaforPresence

final class ZoomMeetingDetectorTests: XCTestCase {
    func test_zoomOwnedInput_detectsMeetingWithoutLegacyHelper() {
        let detector = makeDetector()
        let activity = MicrophoneActivitySnapshot(
            isActiveByAnotherApplication: true,
            activeBundleIdentifiers: ["us.zoom.xos"]
        )

        XCTAssertTrue(detector.isMeetingActive(microphoneActivity: activity))
    }

    func test_currentZoomCaptureHostInput_detectsMeeting() {
        let detector = makeDetector()
        let activity = MicrophoneActivitySnapshot(
            isActiveByAnotherApplication: true,
            activeBundleIdentifiers: ["us.zoom.caphost"]
        )

        XCTAssertTrue(detector.isMeetingActive(microphoneActivity: activity))
    }

    func test_unrelatedInputWhileZoomHelpersAreIdle_doesNotDetectMeeting() {
        let detector = makeDetector()
        let activity = MicrophoneActivitySnapshot(
            isActiveByAnotherApplication: true,
            activeBundleIdentifiers: ["com.example.Dictation"]
        )

        XCTAssertFalse(detector.isMeetingActive(microphoneActivity: activity))
    }

    func test_activeZoomPowerAssertion_detectsMutedListeningMeeting() {
        let detector = ZoomMeetingDetector(
            isProcessRunning: { _ in false },
            hasActiveZoomPowerAssertion: { true }
        )

        XCTAssertTrue(
            detector.isMeetingActive(
                microphoneActivity: MicrophoneActivitySnapshot(
                    isActiveByAnotherApplication: false
                )
            )
        )
    }

    func test_legacyCaptureHost_remainsSupported() {
        let detector = ZoomMeetingDetector(
            isProcessRunning: { $0 == ["CptHost"] },
            hasActiveZoomPowerAssertion: { false }
        )

        XCTAssertTrue(detector.isMeetingActive())
    }

    func test_zoomPowerAssertionReduction_ignoresOtherProcessesAndInactiveLevels() {
        let assertions = [
            ProcessPowerAssertion(
                processIdentifier: 100,
                assertionType: "PreventUserIdleDisplaySleep",
                level: 255
            ),
            ProcessPowerAssertion(
                processIdentifier: 200,
                assertionType: "PreventUserIdleDisplaySleep",
                level: 0
            ),
            ProcessPowerAssertion(
                processIdentifier: 200,
                assertionType: "PreventUserIdleSystemSleep",
                level: 255
            ),
        ]
        let bundleIdentifiers: [pid_t: String] = [
            100: "com.example.VideoPlayer",
            200: "us.zoom.xos",
        ]

        XCTAssertFalse(
            ZoomPowerAssertionSignal.containsZoomMeetingAssertion(
                assertions,
                bundleIdentifier: { bundleIdentifiers[$0] }
            )
        )
    }

    func test_zoomPowerAssertionReduction_acceptsLegacyAndCurrentDisplayAssertions() {
        for assertionType in [
            "NoDisplaySleepAssertion",
            "PreventUserIdleDisplaySleep",
        ] {
            let assertions = [
                ProcessPowerAssertion(
                    processIdentifier: 200,
                    assertionType: assertionType,
                    level: 255
                ),
            ]

            XCTAssertTrue(
                ZoomPowerAssertionSignal.containsZoomMeetingAssertion(
                    assertions,
                    bundleIdentifier: { _ in "us.zoom.xos" }
                ),
                "Expected \(assertionType) to identify an active Zoom meeting"
            )
        }
    }

    func test_zoomPowerAssertionReduction_acceptsCurrentCaptureHostOwner() {
        let assertions = [
            ProcessPowerAssertion(
                processIdentifier: 200,
                assertionType: "PreventUserIdleDisplaySleep",
                level: 255
            ),
        ]

        XCTAssertTrue(
            ZoomPowerAssertionSignal.containsZoomMeetingAssertion(
                assertions,
                bundleIdentifier: { _ in "us.zoom.caphost" }
            )
        )
    }

    private func makeDetector() -> ZoomMeetingDetector {
        ZoomMeetingDetector(
            isProcessRunning: { _ in false },
            hasActiveZoomPowerAssertion: { false }
        )
    }
}
