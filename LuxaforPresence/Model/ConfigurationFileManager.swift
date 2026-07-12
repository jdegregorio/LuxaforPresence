import Foundation

struct ConfigurationFileManager {
    enum ConfigurationError: LocalizedError {
        case bundledTemplateMissing

        var errorDescription: String? {
            switch self {
            case .bundledTemplateMissing:
                return "The bundled configuration template is missing. Reinstall LuxaforPresence and try again."
            }
        }
    }

    let configurationURL: URL
    private let fileManager: FileManager
    private let bundledTemplateURL: () -> URL?

    init(
        configurationURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/LuxaforPresence/config.plist"),
        fileManager: FileManager = .default,
        bundledTemplateURL: @escaping () -> URL? = {
            Bundle.module.url(forResource: "config", withExtension: "plist")
        }
    ) {
        self.configurationURL = configurationURL
        self.fileManager = fileManager
        self.bundledTemplateURL = bundledTemplateURL
    }

    func createFromTemplateIfNeeded() throws -> URL {
        if fileManager.fileExists(atPath: configurationURL.path) {
            return configurationURL
        }

        let directoryURL = configurationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        guard let templateURL = bundledTemplateURL() else {
            throw ConfigurationError.bundledTemplateMissing
        }
        try fileManager.copyItem(at: templateURL, to: configurationURL)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: configurationURL.path
        )
        return configurationURL
    }
}
