import XCTest
@testable import LuxaforPresence

final class ApplicationVersionTests: XCTestCase {
    func test_versionAndBuild_rendersCompleteMenuTitle() {
        let title = ApplicationVersion.menuTitle(infoDictionary: [
            "CFBundleShortVersionString": "1.7.0",
            "CFBundleVersion": "5",
        ])

        XCTAssertEqual(title, "Version: 1.7.0 (Build 5)")
    }

    func test_missingBuild_rendersShortVersionOnly() {
        let title = ApplicationVersion.menuTitle(infoDictionary: [
            "CFBundleShortVersionString": "1.7.0",
        ])

        XCTAssertEqual(title, "Version: 1.7.0")
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
