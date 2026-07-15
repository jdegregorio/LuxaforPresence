import XCTest
@testable import LuxaforPresence

final class ConfigValidationTests: XCTestCase {
    func test_init_usesSafeDefaults_whenRuntimeNumbersAreInvalid() {
        let config = PresenceEngine.Config(values: [
            "pollInterval": 0.01,
            "vadThreshold": 1.01,
            "vadMinimumActiveMilliseconds": -1,
            "recentVoiceSeconds": -1,
            "voiceCooldownSeconds": -1,
            "localOutputReassertSeconds": 1,
            "outputBrightness": 1.01,
        ])

        XCTAssertEqual(config.pollInterval, PresenceEngine.Config.defaultPollInterval)
        XCTAssertEqual(config.vadThreshold, PresenceEngine.Config.defaultVadThreshold)
        XCTAssertEqual(
            config.vadMinimumActiveMilliseconds,
            PresenceEngine.Config.defaultVadMinimumActiveMilliseconds
        )
        XCTAssertEqual(
            config.recentVoiceSeconds,
            PresenceEngine.Config.defaultRecentVoiceSeconds
        )
        XCTAssertEqual(
            config.voiceCooldownSeconds,
            PresenceEngine.Config.defaultVoiceCooldownSeconds
        )
        XCTAssertEqual(
            config.localOutputReassertSeconds,
            PresenceEngine.Config.defaultLocalOutputReassertSeconds
        )
        XCTAssertEqual(
            config.outputBrightness,
            PresenceEngine.Config.defaultOutputBrightness
        )
    }

    func test_init_acceptsBoundaryRuntimeNumbers() {
        let config = PresenceEngine.Config(values: [
            "pollInterval": PresenceEngine.Config.minimumPollInterval,
            "vadThreshold": 1.0,
            "vadMinimumActiveMilliseconds": PresenceEngine.Config.minimumVadMinimumActiveMilliseconds,
            "recentVoiceSeconds": 0.0,
            "voiceCooldownSeconds": 0.0,
            "localOutputReassertSeconds": PresenceEngine.Config.minimumLocalOutputReassertSeconds,
            "outputBrightness": 0,
        ])

        XCTAssertEqual(config.pollInterval, PresenceEngine.Config.minimumPollInterval)
        XCTAssertEqual(config.vadThreshold, 1.0)
        XCTAssertEqual(
            config.vadMinimumActiveMilliseconds,
            PresenceEngine.Config.minimumVadMinimumActiveMilliseconds
        )
        XCTAssertEqual(config.vadMinimumActiveDuration, 0.25)
        XCTAssertEqual(config.recentVoiceSeconds, 0.0)
        XCTAssertEqual(config.voiceCooldownSeconds, 0.0)
        XCTAssertEqual(
            config.localOutputReassertSeconds,
            PresenceEngine.Config.minimumLocalOutputReassertSeconds
        )
        XCTAssertEqual(config.outputBrightness, 0)
    }

    func test_init_rejectsBooleanValuesForNumericKeys() {
        let config = PresenceEngine.Config(values: [
            "pollInterval": true,
            "vadThreshold": false,
            "vadMinimumActiveMilliseconds": true,
            "recentVoiceSeconds": true,
            "voiceCooldownSeconds": false,
            "localOutputReassertSeconds": false,
            "outputBrightness": true,
        ])

        XCTAssertEqual(config.pollInterval, PresenceEngine.Config.defaultPollInterval)
        XCTAssertEqual(config.vadThreshold, PresenceEngine.Config.defaultVadThreshold)
        XCTAssertEqual(
            config.vadMinimumActiveMilliseconds,
            PresenceEngine.Config.defaultVadMinimumActiveMilliseconds
        )
        XCTAssertEqual(
            config.recentVoiceSeconds,
            PresenceEngine.Config.defaultRecentVoiceSeconds
        )
        XCTAssertEqual(
            config.voiceCooldownSeconds,
            PresenceEngine.Config.defaultVoiceCooldownSeconds
        )
        XCTAssertEqual(
            config.localOutputReassertSeconds,
            PresenceEngine.Config.defaultLocalOutputReassertSeconds
        )
        XCTAssertEqual(
            config.outputBrightness,
            PresenceEngine.Config.defaultOutputBrightness
        )
    }

    func test_init_rejectsNonFiniteRuntimeNumbers() {
        let config = PresenceEngine.Config(values: [
            "pollInterval": Double.infinity,
            "vadThreshold": Double.nan,
            "vadMinimumActiveMilliseconds": Double.infinity,
            "recentVoiceSeconds": Double.infinity,
            "voiceCooldownSeconds": Double.nan,
            "localOutputReassertSeconds": Double.nan,
            "outputBrightness": Double.infinity,
        ])

        XCTAssertEqual(config.pollInterval, PresenceEngine.Config.defaultPollInterval)
        XCTAssertEqual(config.vadThreshold, PresenceEngine.Config.defaultVadThreshold)
        XCTAssertEqual(
            config.vadMinimumActiveMilliseconds,
            PresenceEngine.Config.defaultVadMinimumActiveMilliseconds
        )
        XCTAssertEqual(
            config.recentVoiceSeconds,
            PresenceEngine.Config.defaultRecentVoiceSeconds
        )
        XCTAssertEqual(
            config.voiceCooldownSeconds,
            PresenceEngine.Config.defaultVoiceCooldownSeconds
        )
        XCTAssertEqual(
            config.localOutputReassertSeconds,
            PresenceEngine.Config.defaultLocalOutputReassertSeconds
        )
        XCTAssertEqual(
            config.outputBrightness,
            PresenceEngine.Config.defaultOutputBrightness
        )
    }

    func test_init_acceptsIndependentVoiceDurations() {
        let config = PresenceEngine.Config(values: [
            "recentVoiceSeconds": 5.5,
            "voiceCooldownSeconds": 10.25,
        ])

        XCTAssertEqual(config.recentVoiceSeconds, 5.5)
        XCTAssertEqual(config.voiceCooldownSeconds, 10.25)
    }

    func test_init_acceptsLegacyRecentVoiceDurationKey() {
        let config = PresenceEngine.Config(values: [
            "recentVoiceBlinkSeconds": 12.5,
        ])

        XCTAssertEqual(config.recentVoiceSeconds, 12.5)
    }

    func test_init_prefersNewRecentVoiceDurationKeyOverLegacyKey() {
        let config = PresenceEngine.Config(values: [
            "recentVoiceSeconds": 25.0,
            "recentVoiceBlinkSeconds": 12.5,
        ])

        XCTAssertEqual(config.recentVoiceSeconds, 25.0)
    }

    func test_init_acceptsConfiguredOutputBrightness() {
        let config = PresenceEngine.Config(values: [
            "outputBrightness": 0.45,
        ])

        XCTAssertEqual(config.outputBrightness, 0.45)
    }

    func test_init_acceptsZoomDetectionFlag() {
        let config = PresenceEngine.Config(values: [
            "detectZoom": false,
        ])

        XCTAssertFalse(config.detectZoom)
    }

    func test_init_acceptsVoiceDebounceAndRecoveryIntervals() {
        let config = PresenceEngine.Config(values: [
            "vadMinimumActiveMilliseconds": 400,
            "localOutputReassertSeconds": 45,
        ])

        XCTAssertEqual(config.vadMinimumActiveMilliseconds, 400)
        XCTAssertEqual(config.vadMinimumActiveDuration, 0.4)
        XCTAssertEqual(config.localOutputReassertSeconds, 45)
    }

    func test_init_enablesLocalOutputHeartbeatOnlyWhenExplicitlyConfigured() {
        let defaults = PresenceEngine.Config(values: [:])
        let enabled = PresenceEngine.Config(values: [
            "localOutputHeartbeatEnabled": true,
        ])

        XCTAssertFalse(defaults.localOutputHeartbeatEnabled)
        XCTAssertTrue(enabled.localOutputHeartbeatEnabled)
    }

    func test_init_rejectsVoiceDebounceBelowRequiredMinimum() {
        let config = PresenceEngine.Config(values: [
            "vadMinimumActiveMilliseconds": 249.999,
        ])

        XCTAssertEqual(
            config.vadMinimumActiveMilliseconds,
            PresenceEngine.Config.defaultVadMinimumActiveMilliseconds
        )
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
