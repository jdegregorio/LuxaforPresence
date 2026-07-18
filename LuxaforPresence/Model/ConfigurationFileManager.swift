import Foundation

struct ConfigurationFileManager {
    let configurationURL: URL
    private let fileManager: FileManager
    private let alternateConfigurationURLs: [URL]

    init(
        configurationURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/LuxaforPresence/config.plist"),
        fileManager: FileManager = .default,
        alternateConfigurationURLs: [URL] = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).map { $0.appendingPathComponent("LuxaforPresence/config.plist") }
    ) {
        self.configurationURL = configurationURL
        self.fileManager = fileManager
        self.alternateConfigurationURLs = alternateConfigurationURLs
    }

    /// Writes a complete, normalized configuration and drops obsolete or
    /// unrecognized keys from an older file.
    @discardableResult
    func save(_ config: PresenceEngine.Config) throws -> URL {
        let destinationURL = existingConfigurationURL ?? configurationURL
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try PropertyListSerialization.data(
            fromPropertyList: config.propertyListValues,
            format: .xml,
            options: 0
        )
        try data.write(to: destinationURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: destinationURL.path
        )
        return destinationURL
    }

    var existingConfigurationURL: URL? {
        ([configurationURL] + alternateConfigurationURLs).first {
            fileManager.fileExists(atPath: $0.path)
        }
    }
}
