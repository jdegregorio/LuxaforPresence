import XCTest
@testable import LuxaforPresence

final class LuxaforColorTests: XCTestCase {
    func test_applyingBrightness_scalesAndRoundsAllComponents() {
        let color = LuxaforColor(red: 255, green: 101, blue: 1)

        XCTAssertEqual(
            color.applyingBrightness(0.7),
            LuxaforColor(red: 179, green: 71, blue: 1)
        )
    }

    func test_applyingBrightness_clampsOutOfRangeValues() {
        XCTAssertEqual(LuxaforColor.red.applyingBrightness(-1), .off)
        XCTAssertEqual(LuxaforColor.red.applyingBrightness(2), .red)
        XCTAssertEqual(LuxaforColor.red.applyingBrightness(.infinity), .red)
    }

    func test_signalTimeline_usesDistinctSolidColors() {
        XCTAssertEqual(PresenceState.voiceRecent.lightOutput, .solid(.red))
        XCTAssertEqual(PresenceState.voiceCooldown.lightOutput, .solid(.orange))
        XCTAssertEqual(PresenceState.zoomQuiet.lightOutput, .solid(.yellow))
        XCTAssertEqual(PresenceState.voiceRecent.lightOutput.displayName, "Solid Red")
        XCTAssertEqual(PresenceState.voiceCooldown.lightOutput.displayName, "Solid Orange")
        XCTAssertEqual(LuxaforColor.orange.hex, "FF8C00")
        XCTAssertEqual(
            LuxaforColor.orange.applyingBrightness(0.7),
            LuxaforColor(red: 179, green: 98, blue: 0)
        )
    }
}
