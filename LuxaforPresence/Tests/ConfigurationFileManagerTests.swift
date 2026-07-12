import XCTest
@testable import LuxaforPresence

final class ConfigurationFileManagerTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectoryURL)
    }

    func test_createFromTemplateIfNeeded_createsPrivateConfigurationFile() throws {
        let templateURL = temporaryDirectoryURL.appendingPathComponent("template.plist")
        let configurationURL = temporaryDirectoryURL.appendingPathComponent("nested/config.plist")
        try Data("template".utf8).write(to: templateURL)
        let manager = ConfigurationFileManager(
            configurationURL: configurationURL,
            alternateConfigurationURLs: [],
            bundledTemplateURL: { templateURL }
        )

        let result = try manager.createFromTemplateIfNeeded()

        XCTAssertEqual(result, configurationURL)
        XCTAssertEqual(try String(contentsOf: configurationURL), "template")
        let attributes = try FileManager.default.attributesOfItem(atPath: configurationURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func test_createFromTemplateIfNeeded_preservesExistingConfiguration() throws {
        let configurationURL = temporaryDirectoryURL.appendingPathComponent("config.plist")
        try Data("user settings".utf8).write(to: configurationURL)
        let manager = ConfigurationFileManager(
            configurationURL: configurationURL,
            alternateConfigurationURLs: [],
            bundledTemplateURL: {
                XCTFail("Existing configuration should not load the template")
                return nil
            }
        )

        _ = try manager.createFromTemplateIfNeeded()

        XCTAssertEqual(try String(contentsOf: configurationURL), "user settings")
    }

    func test_createFromTemplateIfNeeded_preservesAlternateApplicationSupportConfiguration() throws {
        let preferredURL = temporaryDirectoryURL.appendingPathComponent("dot-config/config.plist")
        let alternateURL = temporaryDirectoryURL.appendingPathComponent("application-support/config.plist")
        try FileManager.default.createDirectory(
            at: alternateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("existing settings".utf8).write(to: alternateURL)
        let manager = ConfigurationFileManager(
            configurationURL: preferredURL,
            alternateConfigurationURLs: [alternateURL],
            bundledTemplateURL: {
                XCTFail("An existing alternate configuration should not load the template")
                return nil
            }
        )

        let result = try manager.createFromTemplateIfNeeded()

        XCTAssertEqual(result, alternateURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: preferredURL.path))
        XCTAssertEqual(try String(contentsOf: alternateURL), "existing settings")
    }

    func test_createFromTemplateIfNeeded_reportsMissingTemplate() {
        let manager = ConfigurationFileManager(
            configurationURL: temporaryDirectoryURL.appendingPathComponent("config.plist"),
            alternateConfigurationURLs: [],
            bundledTemplateURL: { nil }
        )

        XCTAssertThrowsError(try manager.createFromTemplateIfNeeded()) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "The bundled configuration template is missing. Reinstall LuxaforPresence and try again."
            )
        }
    }
}
