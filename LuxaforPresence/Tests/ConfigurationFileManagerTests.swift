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
            bundledTemplateURL: {
                XCTFail("Existing configuration should not load the template")
                return nil
            }
        )

        _ = try manager.createFromTemplateIfNeeded()

        XCTAssertEqual(try String(contentsOf: configurationURL), "user settings")
    }

    func test_createFromTemplateIfNeeded_reportsMissingTemplate() {
        let manager = ConfigurationFileManager(
            configurationURL: temporaryDirectoryURL.appendingPathComponent("config.plist"),
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
