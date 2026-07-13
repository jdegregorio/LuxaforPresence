import Foundation

enum AppResourceBundle {
    private static let bundleName = "LuxaforPresence_LuxaforPresence.bundle"

    static let bundle = locate(in: .main) {
        .module
    }

    static func locate(in mainBundle: Bundle, fallback: () -> Bundle) -> Bundle {
        if let resourcesURL = mainBundle.resourceURL,
           let packagedBundle = Bundle(
               url: resourcesURL.appendingPathComponent(bundleName, isDirectory: true)
           ) {
            return packagedBundle
        }
        return fallback()
    }
}
