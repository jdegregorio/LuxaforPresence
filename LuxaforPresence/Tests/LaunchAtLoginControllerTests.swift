import Foundation
import XCTest
@testable import LuxaforPresence

final class LaunchAtLoginControllerTests: XCTestCase {
    func test_installedLocation_acceptsSystemAndUserApplicationsDirectories() {
        let homeApplications = URL(fileURLWithPath: "/Users/test/Applications")
        let roots = [URL(fileURLWithPath: "/Applications"), homeApplications]

        XCTAssertTrue(
            InstalledApplicationLocation.isEligible(
                bundleURL: URL(fileURLWithPath: "/Applications/LuxaforPresence.app"),
                applicationDirectories: roots
            )
        )
        XCTAssertTrue(
            InstalledApplicationLocation.isEligible(
                bundleURL: homeApplications.appendingPathComponent("LuxaforPresence.app"),
                applicationDirectories: roots
            )
        )
    }

    func test_installedLocation_rejectsMountedTranslocatedAndUnpackagedPaths() {
        let roots = [URL(fileURLWithPath: "/Applications")]

        XCTAssertFalse(
            InstalledApplicationLocation.isEligible(
                bundleURL: URL(fileURLWithPath: "/Volumes/Luxafor/LuxaforPresence.app"),
                applicationDirectories: roots
            )
        )
        XCTAssertFalse(
            InstalledApplicationLocation.isEligible(
                bundleURL: URL(fileURLWithPath: "/private/var/folders/AppTranslocation/LuxaforPresence.app"),
                applicationDirectories: roots
            )
        )
        XCTAssertFalse(
            InstalledApplicationLocation.isEligible(
                bundleURL: URL(fileURLWithPath: "/tmp/LuxaforPresence"),
                applicationDirectories: roots
            )
        )
    }

    func test_ensureEnabled_firstInstalledLaunch_registersAndPersistsIntent() throws {
        let service = FakeLaunchAtLoginService(status: .disabled)
        let preferences = FakeLaunchAtLoginPreferences()
        let controller = makeController(service: service, preferences: preferences)

        let status = try controller.ensureEnabled()

        XCTAssertEqual(status, .enabled)
        XCTAssertEqual(service.registerCount, 1)
        XCTAssertEqual(preferences.userPreference, true)
    }

    func test_ensureEnabled_whenAlreadyEnabled_doesNotRegisterAgain() throws {
        let service = FakeLaunchAtLoginService(status: .enabled)
        let preferences = FakeLaunchAtLoginPreferences()
        let controller = makeController(service: service, preferences: preferences)

        XCTAssertEqual(try controller.ensureEnabled(), .enabled)

        XCTAssertEqual(service.registerCount, 0)
        XCTAssertEqual(preferences.userPreference, true)
    }

    func test_ensureEnabled_whenApprovalRequired_doesNotRegisterRepeatedly() throws {
        let service = FakeLaunchAtLoginService(status: .requiresApproval)
        let preferences = FakeLaunchAtLoginPreferences()
        let controller = makeController(service: service, preferences: preferences)

        XCTAssertEqual(try controller.ensureEnabled(), .requiresApproval)
        XCTAssertEqual(try controller.ensureEnabled(), .requiresApproval)

        XCTAssertEqual(service.registerCount, 0)
        XCTAssertEqual(preferences.userPreference, true)
    }

    func test_userOptOut_isNotReenabledOnFutureLaunch() throws {
        let service = FakeLaunchAtLoginService(status: .enabled)
        let preferences = FakeLaunchAtLoginPreferences()
        let controller = makeController(service: service, preferences: preferences)
        _ = try controller.setEnabled(false)
        let nextLaunchController = makeController(
            service: service,
            preferences: preferences
        )

        let status = try nextLaunchController.ensureEnabled()

        XCTAssertEqual(status, .disabled)
        XCTAssertEqual(service.registerCount, 0)
        XCTAssertEqual(service.unregisterCount, 1)
        XCTAssertEqual(preferences.userPreference, false)
    }

    func test_ensureEnabled_withOptOutReconcilesUnexpectedEnabledService() throws {
        let service = FakeLaunchAtLoginService(status: .enabled)
        let preferences = FakeLaunchAtLoginPreferences(userPreference: false)
        let controller = makeController(service: service, preferences: preferences)

        let status = try controller.ensureEnabled()

        XCTAssertEqual(status, .disabled)
        XCTAssertEqual(service.unregisterCount, 1)
    }

    func test_transientRegisterFailure_keepsIntentForNextLaunchRetry() {
        let service = FakeLaunchAtLoginService(
            status: .disabled,
            registerFailures: 1
        )
        let preferences = FakeLaunchAtLoginPreferences()
        let controller = makeController(service: service, preferences: preferences)

        XCTAssertThrowsError(try controller.ensureEnabled())
        XCTAssertEqual(preferences.userPreference, true)
        XCTAssertNoThrow(try controller.ensureEnabled())
        XCTAssertEqual(service.registerCount, 2)
        XCTAssertEqual(service.status, .enabled)
    }

    func test_transientUnregisterFailure_keepsOptOutForNextLaunchRetry() {
        let service = FakeLaunchAtLoginService(
            status: .enabled,
            unregisterFailures: 1
        )
        let preferences = FakeLaunchAtLoginPreferences()
        let controller = makeController(service: service, preferences: preferences)

        XCTAssertThrowsError(try controller.setEnabled(false))
        XCTAssertEqual(preferences.userPreference, false)
        XCTAssertNoThrow(try controller.ensureEnabled())
        XCTAssertEqual(service.unregisterCount, 2)
        XCTAssertEqual(service.status, .disabled)
    }

    func test_requiresApproval_opensSystemSettingsWithoutRegisteringAgain() throws {
        let service = FakeLaunchAtLoginService(status: .requiresApproval)
        let preferences = FakeLaunchAtLoginPreferences()
        let controller = makeController(service: service, preferences: preferences)

        _ = try controller.setEnabled(true)

        XCTAssertEqual(service.openSettingsCount, 1)
        XCTAssertEqual(service.registerCount, 0)
        XCTAssertEqual(preferences.userPreference, true)
    }

    func test_uninstalledProcess_isUnavailableAndDoesNotMutateServiceOrPreferences() throws {
        let service = FakeLaunchAtLoginService(status: .disabled)
        let preferences = FakeLaunchAtLoginPreferences()
        let controller = LaunchAtLoginController(
            isPackagedApplication: { false },
            service: service,
            preferenceStore: preferences
        )

        XCTAssertEqual(try controller.ensureEnabled(), .requiresInstallation)
        XCTAssertEqual(service.registerCount, 0)
        XCTAssertNil(preferences.userPreference)
    }

    func test_installedProcessWithMissingService_isUnavailableNotUninstalled() throws {
        let service = FakeLaunchAtLoginService(status: .unavailable)
        let preferences = FakeLaunchAtLoginPreferences()
        let controller = makeController(service: service, preferences: preferences)

        XCTAssertEqual(try controller.ensureEnabled(), .unavailable)
        XCTAssertEqual(service.registerCount, 0)
        XCTAssertNil(preferences.userPreference)
    }

    private func makeController(
        service: FakeLaunchAtLoginService,
        preferences: FakeLaunchAtLoginPreferences
    ) -> LaunchAtLoginController {
        LaunchAtLoginController(
            isPackagedApplication: { true },
            service: service,
            preferenceStore: preferences
        )
    }
}

private final class FakeLaunchAtLoginPreferences: LaunchAtLoginPreferenceStoring {
    var userPreference: Bool?

    init(userPreference: Bool? = nil) {
        self.userPreference = userPreference
    }
}

private final class FakeLaunchAtLoginService: LaunchAtLoginServiceProtocol {
    enum TestError: Error {
        case failed
    }

    var status: LaunchAtLoginStatus
    private var registerFailures: Int
    private var unregisterFailures: Int
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var openSettingsCount = 0

    init(
        status: LaunchAtLoginStatus,
        registerFailures: Int = 0,
        unregisterFailures: Int = 0
    ) {
        self.status = status
        self.registerFailures = registerFailures
        self.unregisterFailures = unregisterFailures
    }

    func register() throws {
        registerCount += 1
        if registerFailures > 0 {
            registerFailures -= 1
            throw TestError.failed
        }
        status = .enabled
    }

    func unregister() throws {
        unregisterCount += 1
        if unregisterFailures > 0 {
            unregisterFailures -= 1
            throw TestError.failed
        }
        status = .disabled
    }

    func openSystemSettings() {
        openSettingsCount += 1
    }
}
