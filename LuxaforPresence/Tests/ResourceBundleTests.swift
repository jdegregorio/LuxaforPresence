import Foundation
import XCTest
@testable import LuxaforPresence

final class ResourceBundleTests: XCTestCase {
    func test_locator_prefersPackagedResourceBundle_withoutEvaluatingFallback() throws {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let appURL = temporaryURL.appendingPathComponent("Test.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let resourceBundleURL = resourcesURL.appendingPathComponent(
            "LuxaforPresence_LuxaforPresence.bundle",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: resourceBundleURL, withIntermediateDirectories: true)
        try writeInfoPlist(
            [
                "CFBundleIdentifier": "com.example.LuxaforPresenceTests",
                "CFBundlePackageType": "APPL",
            ],
            to: contentsURL.appendingPathComponent("Info.plist")
        )
        try writeInfoPlist(
            [
                "CFBundleIdentifier": "com.example.LuxaforPresenceTests.Resources",
                "CFBundlePackageType": "BNDL",
            ],
            to: resourceBundleURL.appendingPathComponent("Info.plist")
        )

        let mainBundle = try XCTUnwrap(Bundle(url: appURL))
        var usedFallback = false
        let locatedBundle = AppResourceBundle.locate(in: mainBundle) {
            usedFallback = true
            return .module
        }

        XCTAssertFalse(usedFallback)
        XCTAssertEqual(
            locatedBundle.bundleURL.standardizedFileURL,
            resourceBundleURL.standardizedFileURL
        )
    }

    func test_locator_usesSwiftPMFallback_whenPackagedBundleIsMissing() throws {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let appURL = temporaryURL.appendingPathComponent("Test.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        try writeInfoPlist(
            [
                "CFBundleIdentifier": "com.example.LuxaforPresenceTests.MissingResources",
                "CFBundlePackageType": "APPL",
            ],
            to: contentsURL.appendingPathComponent("Info.plist")
        )

        let mainBundle = try XCTUnwrap(Bundle(url: appURL))
        var usedFallback = false
        let locatedBundle = AppResourceBundle.locate(in: mainBundle) {
            usedFallback = true
            return .module
        }

        XCTAssertTrue(usedFallback)
        XCTAssertEqual(locatedBundle.bundleURL, Bundle.module.bundleURL)
    }

    func test_configLoadsDefaultsFromSwiftPMResourceBundle_whenUserConfigIsAbsent() {
        let config = PresenceEngine.Config(userConfigURLs: [])

        XCTAssertEqual(config.enabledMeetingDetectors, Set(["Zoom"]))
        XCTAssertEqual(config.recentVoiceBlinkSeconds, 300)
        XCTAssertEqual(config.voiceCooldownSeconds, 300)
    }

    func test_appResourceBundle_containsConfigAndStatusIcons() {
        let resources: [(name: String, extensionName: String, subdirectory: String?)] = [
            ("config", "plist", nil),
            ("circle.circle.fill", "png", "Assets.xcassets/StatusIconOn.imageset"),
            ("circle", "png", "Assets.xcassets/StatusIconOff.imageset"),
            ("questionmark.circle", "png", "Assets.xcassets/StatusIconIdle.imageset"),
        ]

        for (name, extensionName, subdirectory) in resources {
            XCTAssertNotNil(
                AppResourceBundle.bundle.url(
                    forResource: name,
                    withExtension: extensionName,
                    subdirectory: subdirectory
                ),
                "Missing bundled resource: \(name).\(extensionName)"
            )
        }
    }

    private func writeInfoPlist(_ values: [String: String], to url: URL) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: values,
            format: .xml,
            options: 0
        )
        try data.write(to: url)
    }
}
