import Foundation
import XCTest
@testable import LuxaforPresence

final class MinimalPermissionsTests: XCTestCase {
    func test_infoPlist_declaresOnlyMicrophonePrivacyUsage() throws {
        let info = try loadPlist(named: "Info.plist")

        XCTAssertEqual(
            info["CFBundleIdentifier"] as? String,
            "com.jdegregorio.LuxaforPresence"
        )
        XCTAssertEqual(info["CFBundlePackageType"] as? String, "APPL")
        XCTAssertEqual(info["LSMinimumSystemVersion"] as? String, "13.0")
        XCTAssertEqual(info["LSUIElement"] as? Bool, true)
        XCTAssertNotNil(info["NSMicrophoneUsageDescription"])
        XCTAssertNil(info["NSCameraUsageDescription"])
        XCTAssertNil(info["NSCameraUseContinuityCameraDeviceType"])
        XCTAssertNil(info["NSCalendarsUsageDescription"])
        XCTAssertNil(info["NSAppleEventsUsageDescription"])
    }

    func test_entitlements_includeAudioInputButNotCamera() throws {
        let entitlements = try loadPlist(named: "LuxaforPresence.entitlements")

        XCTAssertEqual(entitlements["com.apple.security.device.audio-input"] as? Bool, true)
        XCTAssertNil(entitlements["com.apple.security.device.camera"])
        XCTAssertEqual(
            Set(entitlements.keys),
            Set(["com.apple.security.device.audio-input"])
        )
    }

    func test_bundledConfiguration_omitsUnusedDetectorKeys() throws {
        let configURL = try XCTUnwrap(
            AppResourceBundle.bundle.url(forResource: "config", withExtension: "plist")
        )
        let data = try Data(contentsOf: configURL)
        let values = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        )

        XCTAssertEqual(values["detectZoom"] as? Bool, true)
        XCTAssertNil(values["meetingBundles"])
        XCTAssertNil(values["enabledMeetingDetectors"])
        XCTAssertNil(values["useCalendar"])
        XCTAssertNil(values["useCamera"])
        XCTAssertNil(values["debugAssumeFrontmostImpliesMic"])
    }

    private func loadPlist(named name: String) throws -> [String: Any] {
        let sourceDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: sourceDirectory.appendingPathComponent(name))
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        )
    }
}
