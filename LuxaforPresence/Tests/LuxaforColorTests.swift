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

    func test_voiceStates_useTheSameSolidPurpleOutput() {
        XCTAssertEqual(PresenceState.voiceRecent.lightOutput, .solid(.purple))
        XCTAssertEqual(PresenceState.voiceCooldown.lightOutput, .solid(.purple))
        XCTAssertEqual(PresenceState.voiceRecent.lightOutput.displayName, "Solid Purple")
        XCTAssertEqual(LuxaforColor.purple.hex, "8B5CF6")
    }
}
