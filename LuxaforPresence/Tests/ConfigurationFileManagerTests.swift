import XCTest
@testable import LuxaforPresence

final class ConfigurationFileManagerTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectoryURL)
    }

    func test_save_createsPrivateNormalizedConfigurationFile() throws {
        let configurationURL = temporaryDirectoryURL
            .appendingPathComponent("nested/config.plist")
        let manager = ConfigurationFileManager(
            configurationURL: configurationURL,
            alternateConfigurationURLs: []
        )
        let config = PresenceEngine.Config(values: [
            "recentVoiceSeconds": 45.0,
            "recentVoiceColor": "#123456",
        ])

        let result = try manager.save(config)

        XCTAssertEqual(result, configurationURL)
        let values = try loadConfiguration(at: configurationURL)
        XCTAssertEqual(values["recentVoiceSeconds"] as? Double, 45)
        XCTAssertEqual(values["recentVoiceColor"] as? String, "#123456")
        XCTAssertEqual(values["zoomVadThreshold"] as? Double, 0.02)
        XCTAssertEqual(values.count, 19)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: configurationURL.path
        )
        XCTAssertEqual(
            (attributes[.posixPermissions] as? NSNumber)?.intValue,
            0o600
        )
    }

    func test_save_migratesOlderRecentDurationAndRemovesObsoleteKey() throws {
        let configurationURL = temporaryDirectoryURL.appendingPathComponent("config.plist")
        let oldValues: [String: Any] = [
            "recentVoiceBlinkSeconds": 10.0,
        ]
        try writeConfiguration(oldValues, to: configurationURL)
        let manager = ConfigurationFileManager(
            configurationURL: configurationURL,
            alternateConfigurationURLs: []
        )

        try manager.save(PresenceEngine.Config(values: oldValues))

        let values = try loadConfiguration(at: configurationURL)
        XCTAssertEqual(values["recentVoiceSeconds"] as? Double, 10)
        XCTAssertNil(values["recentVoiceBlinkSeconds"])
    }

    func test_save_preservesExistingApplicationSupportLocation() throws {
        let preferredURL = temporaryDirectoryURL
            .appendingPathComponent("dot-config/config.plist")
        let alternateURL = temporaryDirectoryURL
            .appendingPathComponent("application-support/config.plist")
        try writeConfiguration(["recentVoiceSeconds": 10], to: alternateURL)
        let manager = ConfigurationFileManager(
            configurationURL: preferredURL,
            alternateConfigurationURLs: [alternateURL]
        )

        let result = try manager.save(
            PresenceEngine.Config(values: ["recentVoiceSeconds": 30.0])
        )

        XCTAssertEqual(result, alternateURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: preferredURL.path))
        let values = try loadConfiguration(at: alternateURL)
        XCTAssertEqual(values["recentVoiceSeconds"] as? Double, 30)
    }

    private func loadConfiguration(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        )
    }

    private func writeConfiguration(_ values: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try PropertyListSerialization.data(
            fromPropertyList: values,
            format: .xml,
            options: 0
        )
        try data.write(to: url)
    }
}
