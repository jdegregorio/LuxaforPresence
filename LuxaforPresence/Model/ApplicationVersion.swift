import Foundation

enum ApplicationVersion {
    static func menuTitle(
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> String {
        let version = normalizedString(
            infoDictionary["CFBundleShortVersionString"]
        )
        let build = normalizedString(infoDictionary["CFBundleVersion"])

        switch (version, build) {
        case let (version?, build?):
            return "Version: \(version) (Build \(build))"
        case let (version?, nil):
            return "Version: \(version)"
        case let (nil, build?):
            return "Build: \(build)"
        case (nil, nil):
            return "Version: Unknown"
        }
    }

    private static func normalizedString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
