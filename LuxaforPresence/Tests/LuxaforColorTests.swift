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

    func test_hexString_acceptsCommonRGBFormatsAndNormalizesOutput() {
        XCTAssertEqual(LuxaforColor(hexString: " #aB10fF "), .init(red: 171, green: 16, blue: 255))
        XCTAssertEqual(LuxaforColor(hexString: "ABCDEF")?.localHex, "#ABCDEF")
        XCTAssertNil(LuxaforColor(hexString: "#12345"))
        XCTAssertNil(LuxaforColor(hexString: "#GG0000"))
    }

    func test_defaultSignalTimeline_usesDistinctSolidColors() {
        let config = PresenceEngine.Config(values: [:])

        XCTAssertEqual(config.lightOutput(for: .voiceRecent), .solid(.red))
        XCTAssertEqual(config.lightOutput(for: .voiceCooldown), .solid(.orange))
        XCTAssertEqual(config.lightOutput(for: .zoomQuiet), .solid(.yellow))
        XCTAssertEqual(config.lightOutput(for: .voiceRecent).displayName, "Solid Red (#FF0000)")
        XCTAssertEqual(config.lightOutput(for: .voiceCooldown).displayName, "Solid Orange (#FF8C00)")
        XCTAssertEqual(LuxaforColor.orange.hex, "FF8C00")
        XCTAssertEqual(
            LuxaforColor.orange.applyingBrightness(0.7),
            LuxaforColor(red: 179, green: 98, blue: 0)
        )
    }
}
