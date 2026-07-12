import Foundation
import XCTest
@testable import LuxaforPresence

final class ResourceBundleTests: XCTestCase {
    func test_configLoadsDefaultsFromSwiftPMResourceBundle_whenUserConfigIsAbsent() {
        let config = PresenceEngine.Config(userConfigURLs: [])

        XCTAssertEqual(
            config.enabledMeetingDetectors,
            Set(["Zoom", "Webex", "Teams", "Slack", "GoogleMeet"])
        )
    }

    func test_moduleBundleContainsConfigAndStatusIcons() {
        let resources: [(name: String, extensionName: String, subdirectory: String?)] = [
            ("config", "plist", nil),
            ("circle.circle.fill", "png", "Assets.xcassets/StatusIconOn.imageset"),
            ("circle", "png", "Assets.xcassets/StatusIconOff.imageset"),
            ("questionmark.circle", "png", "Assets.xcassets/StatusIconIdle.imageset"),
        ]

        for (name, extensionName, subdirectory) in resources {
            XCTAssertNotNil(
                Bundle.module.url(
                    forResource: name,
                    withExtension: extensionName,
                    subdirectory: subdirectory
                ),
                "Missing bundled resource: \(name).\(extensionName)"
            )
        }
    }
}
