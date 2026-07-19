import XCTest
@testable import LuxaforPresence

final class ApplicationVersionTests: XCTestCase {
    func test_versionAndBuild_rendersSemanticVersionOnly() {
        let title = ApplicationVersion.menuTitle(infoDictionary: [
            "CFBundleShortVersionString": "1.9.6",
            "CFBundleVersion": "1.9.6",
        ])

        XCTAssertEqual(title, "Version: 1.9.6")
    }

    func test_missingBuild_rendersShortVersionOnly() {
        let title = ApplicationVersion.menuTitle(infoDictionary: [
            "CFBundleShortVersionString": "1.9.6",
        ])

        XCTAssertEqual(title, "Version: 1.9.6")
    }

    func test_missingVersionMetadata_rendersSafeFallback() {
        XCTAssertEqual(
            ApplicationVersion.menuTitle(infoDictionary: [:]),
            "Version: Unknown"
        )
    }

    func test_blankVersion_usesAvailableBuild() {
        let title = ApplicationVersion.menuTitle(infoDictionary: [
            "CFBundleShortVersionString": "  ",
            "CFBundleVersion": " 5 ",
        ])

        XCTAssertEqual(title, "Build: 5")
    }
}
