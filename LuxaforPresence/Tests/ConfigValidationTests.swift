import XCTest
@testable import LuxaforPresence

final class ConfigValidationTests: XCTestCase {
    func test_init_usesSafeDefaults_whenRuntimeNumbersAreInvalid() {
        let config = PresenceEngine.Config(values: [
            "pollInterval": 0.01,
            "vadThreshold": 1.01,
            "recentVoiceBlinkSeconds": -1,
            "voiceCooldownSeconds": -1,
        ])

        XCTAssertEqual(config.pollInterval, PresenceEngine.Config.defaultPollInterval)
        XCTAssertEqual(config.vadThreshold, PresenceEngine.Config.defaultVadThreshold)
        XCTAssertEqual(
            config.recentVoiceBlinkSeconds,
            PresenceEngine.Config.defaultRecentVoiceBlinkSeconds
        )
        XCTAssertEqual(
            config.voiceCooldownSeconds,
            PresenceEngine.Config.defaultVoiceCooldownSeconds
        )
    }

    func test_init_acceptsBoundaryRuntimeNumbers() {
        let config = PresenceEngine.Config(values: [
            "pollInterval": PresenceEngine.Config.minimumPollInterval,
            "vadThreshold": 1.0,
            "recentVoiceBlinkSeconds": 0.0,
            "voiceCooldownSeconds": 0.0,
        ])

        XCTAssertEqual(config.pollInterval, PresenceEngine.Config.minimumPollInterval)
        XCTAssertEqual(config.vadThreshold, 1.0)
        XCTAssertEqual(config.recentVoiceBlinkSeconds, 0.0)
        XCTAssertEqual(config.voiceCooldownSeconds, 0.0)
    }

    func test_init_rejectsBooleanValuesForNumericKeys() {
        let config = PresenceEngine.Config(values: [
            "pollInterval": true,
            "vadThreshold": false,
            "recentVoiceBlinkSeconds": true,
            "voiceCooldownSeconds": false,
        ])

        XCTAssertEqual(config.pollInterval, PresenceEngine.Config.defaultPollInterval)
        XCTAssertEqual(config.vadThreshold, PresenceEngine.Config.defaultVadThreshold)
        XCTAssertEqual(
            config.recentVoiceBlinkSeconds,
            PresenceEngine.Config.defaultRecentVoiceBlinkSeconds
        )
        XCTAssertEqual(
            config.voiceCooldownSeconds,
            PresenceEngine.Config.defaultVoiceCooldownSeconds
        )
    }

    func test_init_rejectsNonFiniteRuntimeNumbers() {
        let config = PresenceEngine.Config(values: [
            "pollInterval": Double.infinity,
            "vadThreshold": Double.nan,
            "recentVoiceBlinkSeconds": Double.infinity,
            "voiceCooldownSeconds": Double.nan,
        ])

        XCTAssertEqual(config.pollInterval, PresenceEngine.Config.defaultPollInterval)
        XCTAssertEqual(config.vadThreshold, PresenceEngine.Config.defaultVadThreshold)
        XCTAssertEqual(
            config.recentVoiceBlinkSeconds,
            PresenceEngine.Config.defaultRecentVoiceBlinkSeconds
        )
        XCTAssertEqual(
            config.voiceCooldownSeconds,
            PresenceEngine.Config.defaultVoiceCooldownSeconds
        )
    }

    func test_init_acceptsIndependentVoiceDurations() {
        let config = PresenceEngine.Config(values: [
            "recentVoiceBlinkSeconds": 5.5,
            "voiceCooldownSeconds": 10.25,
        ])

        XCTAssertEqual(config.recentVoiceBlinkSeconds, 5.5)
        XCTAssertEqual(config.voiceCooldownSeconds, 10.25)
    }

    func test_init_filtersLegacyMeetingDetectorListToZoom() {
        let config = PresenceEngine.Config(values: [
            "enabledMeetingDetectors": ["Zoom", "Webex", "Teams", "Slack", "GoogleMeet"],
        ])

        XCTAssertEqual(config.enabledMeetingDetectors, Set(["Zoom"]))
    }

    func test_init_allowsZoomToBeExplicitlyDisabled() {
        let config = PresenceEngine.Config(values: [
            "enabledMeetingDetectors": [String](),
        ])

        XCTAssertEqual(config.enabledMeetingDetectors, Set<String>())
    }

    func test_init_fallsBackToLocalTransport_whenRemoteIdIsPlaceholder() {
        let config = PresenceEngine.Config(values: [
            "transportMode": "remote",
            "remoteWebhookUserId": "LUXAFOR_USER_ID_HERE",
        ])

        XCTAssertEqual(config.transportMode, .local)
    }

    func test_init_fallsBackToLocalTransport_whenRemoteIdIsBlank() {
        let config = PresenceEngine.Config(values: [
            "transportMode": " remote ",
            "remoteWebhookUserId": "  ",
        ])

        XCTAssertEqual(config.transportMode, .local)
    }

    func test_init_keepsRemoteTransport_whenRemoteIdIsValid() {
        let config = PresenceEngine.Config(values: [
            "transportMode": "remote",
            "remoteWebhookUserId": " real-user-id ",
        ])

        XCTAssertEqual(config.transportMode, .remote)
        XCTAssertEqual(config.remoteWebhookUserId, "real-user-id")
    }

    func test_init_usesLoopbackDefault_whenLocalWebhookURLIsInvalid() {
        let config = PresenceEngine.Config(values: [
            "localWebhookBaseUrl": "http://example.com/api",
        ])

        XCTAssertEqual(config.localWebhookBaseUrl, LocalWebhookEndpoint.defaultBaseURLString)
    }

    func test_init_preservesValidExternalHTTPSBasePath() {
        let config = PresenceEngine.Config(values: [
            "localWebhookBaseUrl": "https://example.com/luxafor/v1",
        ])

        XCTAssertEqual(config.localWebhookBaseUrl, "https://example.com/luxafor/v1")
    }
}
