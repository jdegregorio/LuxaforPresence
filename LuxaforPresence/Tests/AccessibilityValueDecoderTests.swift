import ApplicationServices
import XCTest
@testable import LuxaforPresence

final class AccessibilityValueDecoderTests: XCTestCase {
    func test_MalformedChildValues_FiltersNonAccessibilityElements() {
        let element = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)

        let decoded = AXValueDecoder.elements(
            from: [element, "not an accessibility element", NSNumber(value: 1)]
        )

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(CFGetTypeID(decoded[0]), AXUIElementGetTypeID())
    }
}
