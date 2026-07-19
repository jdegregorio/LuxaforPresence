import Foundation

final class ZoomMeetingDetector: MeetingDetectorProtocol {
    private static let zoomInputBundleIdentifiers: Set<String> = [
        "us.zoom.caphost",
        "us.zoom.xos",
    ]

    private let isProcessRunning: ([String]) -> Bool
    private let hasActiveZoomPowerAssertion: () -> Bool

    init(
        isProcessRunning: @escaping ([String]) -> Bool = ProcessSignal.isRunning,
        hasActiveZoomPowerAssertion: (() -> Bool)? = nil
    ) {
        self.isProcessRunning = isProcessRunning
        if let hasActiveZoomPowerAssertion {
            self.hasActiveZoomPowerAssertion = hasActiveZoomPowerAssertion
        } else {
            let powerAssertionSignal = ZoomPowerAssertionSignal()
            self.hasActiveZoomPowerAssertion = powerAssertionSignal.isMeetingActive
        }
    }

    var name: String { "Zoom" }

    func isMeetingActive() -> Bool {
        isProcessRunning(["CptHost"])
            || hasActiveZoomPowerAssertion()
    }

    func isMeetingActive(
        microphoneActivity: MicrophoneActivitySnapshot
    ) -> Bool {
        // Current Zoom releases keep `caphost` running while the client is idle,
        // so process presence alone is not a meeting signal. Active Zoom-owned
        // input is call-specific and also arrives early enough to select the
        // longer Zoom signal qualifier before audio sampling starts.
        microphoneActivity.isActive(
            forBundleIdentifiers: Self.zoomInputBundleIdentifiers
        ) || isMeetingActive()
    }
}
