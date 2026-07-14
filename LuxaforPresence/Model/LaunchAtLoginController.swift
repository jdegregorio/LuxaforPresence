import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case requiresInstallation
    case unavailable
}

protocol LaunchAtLoginServiceProtocol: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

protocol LaunchAtLoginControlling: AnyObject {
    var status: LaunchAtLoginStatus { get }
    @discardableResult func ensureEnabled() throws -> LaunchAtLoginStatus
    @discardableResult func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus
    func openSystemSettings()
}

protocol LaunchAtLoginPreferenceStoring: AnyObject {
    var userPreference: Bool? { get set }
}

final class UserDefaultsLaunchAtLoginPreferenceStore: LaunchAtLoginPreferenceStoring {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "LaunchAtLoginEnabled"
    ) {
        self.defaults = defaults
        self.key = key
    }

    var userPreference: Bool? {
        get { defaults.object(forKey: key) as? Bool }
        set {
            if let newValue {
                defaults.set(newValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

enum InstalledApplicationLocation {
    static func isEligible(
        bundleURL: URL,
        applicationDirectories: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true),
        ]
    ) -> Bool {
        guard bundleURL.pathExtension.lowercased() == "app" else { return false }
        let bundlePath = bundleURL.standardizedFileURL.resolvingSymlinksInPath().path
        return applicationDirectories.contains { directory in
            let directoryPath = directory.standardizedFileURL
                .resolvingSymlinksInPath()
                .path
            return bundlePath == directoryPath
                || bundlePath.hasPrefix(directoryPath + "/")
        }
    }
}

final class MainAppLaunchAtLoginService: LaunchAtLoginServiceProtocol {
    private let service = SMAppService.mainApp

    var status: LaunchAtLoginStatus {
        switch service.status {
        case .notRegistered:
            return .disabled
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Owns launch-at-login registration while keeping `swift run` harmless.
final class LaunchAtLoginController: LaunchAtLoginControlling {
    private let isPackagedApplication: () -> Bool
    private let service: LaunchAtLoginServiceProtocol
    private let preferenceStore: LaunchAtLoginPreferenceStoring

    init(
        isPackagedApplication: @escaping () -> Bool = {
            InstalledApplicationLocation.isEligible(bundleURL: Bundle.main.bundleURL)
        },
        service: LaunchAtLoginServiceProtocol = MainAppLaunchAtLoginService(),
        preferenceStore: LaunchAtLoginPreferenceStoring = UserDefaultsLaunchAtLoginPreferenceStore()
    ) {
        self.isPackagedApplication = isPackagedApplication
        self.service = service
        self.preferenceStore = preferenceStore
    }

    var status: LaunchAtLoginStatus {
        guard isPackagedApplication() else { return .requiresInstallation }
        return service.status
    }

    @discardableResult
    func ensureEnabled() throws -> LaunchAtLoginStatus {
        guard isPackagedApplication() else { return .requiresInstallation }
        guard service.status != .unavailable else { return .unavailable }
        if preferenceStore.userPreference == false {
            if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
            return service.status
        }
        preferenceStore.userPreference = true
        if service.status == .disabled {
            try service.register()
        }
        return service.status
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        guard isPackagedApplication() else { return .requiresInstallation }
        switch (enabled, service.status) {
        case (true, .disabled):
            preferenceStore.userPreference = true
            try service.register()
        case (true, .requiresApproval):
            preferenceStore.userPreference = true
            service.openSystemSettings()
        case (false, .enabled), (false, .requiresApproval):
            preferenceStore.userPreference = false
            try service.unregister()
        case (true, .enabled):
            preferenceStore.userPreference = true
        case (false, .disabled):
            preferenceStore.userPreference = false
        default:
            break
        }
        return service.status
    }

    func openSystemSettings() {
        guard isPackagedApplication() else { return }
        service.openSystemSettings()
    }
}
