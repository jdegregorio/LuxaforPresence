import XCTest
@testable import LuxaforPresence

final class ConfigValidationTests: XCTestCase {
    func test_init_usesSafeDefaults_whenRuntimeNumbersAreInvalid() {
        let config = PresenceEngine.Config(values: [
            "pollInterval": 0.01,
            "vadThreshold": 1.01,
            "vadMinimumActiveMilliseconds": -1,
            "recentVoiceBlinkSeconds": -1,
            "voiceCooldownSeconds": -1,
            "blinkIntervalMilliseconds": 0,
            "localOutputReassertSeconds": 1,
        ])

        XCTAssertEqual(config.pollInterval, PresenceEngine.Config.defaultPollInterval)
        XCTAssertEqual(config.vadThreshold, PresenceEngine.Config.defaultVadThreshold)
        XCTAssertEqual(
            config.vadMinimumActiveMilliseconds,
            PresenceEngine.Config.defaultVadMinimumActiveMilliseconds
        )
        XCTAssertEqual(
            config.recentVoiceBlinkSeconds,
            PresenceEngine.Config.defaultRecentVoiceBlinkSeconds
        )
        XCTAssertEqual(
            config.voiceCooldownSeconds,
            PresenceEngine.Config.defaultVoiceCooldownSeconds
        )
        XCTAssertEqual(
            config.blinkIntervalMilliseconds,
            PresenceEngine.Config.defaultBlinkIntervalMilliseconds
        )
        XCTAssertEqual(
            config.localOutputReassertSeconds,
            PresenceEngine.Config.defaultLocalOutputReassertSeconds
        )
    }

    func test_init_acceptsBoundaryRuntimeNumbers() {
        let config = PresenceEngine.Config(values: [
            "pollInterval": PresenceEngine.Config.minimumPollInterval,
            "vadThreshold": 1.0,
            "vadMinimumActiveMilliseconds": PresenceEngine.Config.minimumVadMinimumActiveMilliseconds,
            "recentVoiceBlinkSeconds": 0.0,
            "voiceCooldownSeconds": 0.0,
            "blinkIntervalMilliseconds": PresenceEngine.Config.minimumBlinkIntervalMilliseconds,
            "localOutputReassertSeconds": PresenceEngine.Config.minimumLocalOutputReassertSeconds,
        ])

        XCTAssertEqual(config.pollInterval, PresenceEngine.Config.minimumPollInterval)
        XCTAssertEqual(config.vadThreshold, 1.0)
        XCTAssertEqual(
            config.vadMinimumActiveMilliseconds,
            PresenceEngine.Config.minimumVadMinimumActiveMilliseconds
        )
        XCTAssertEqual(config.vadMinimumActiveDuration, 0.25)
        XCTAssertEqual(config.recentVoiceBlinkSeconds, 0.0)
        XCTAssertEqual(config.voiceCooldownSeconds, 0.0)
        XCTAssertEqual(
            config.blinkIntervalMilliseconds,
            PresenceEngine.Config.minimumBlinkIntervalMilliseconds
        )
        XCTAssertEqual(config.blinkInterval, 0.1)
        XCTAssertEqual(
            config.localOutputReassertSeconds,
            PresenceEngine.Config.minimumLocalOutputReassertSeconds
        )
    }

    func test_init_rejectsBooleanValuesForNumericKeys() {
        let config = PresenceEngine.Config(values: [
            "pollInterval": true,
            "vadThreshold": false,
            "vadMinimumActiveMilliseconds": true,
            "recentVoiceBlinkSeconds": true,
            "voiceCooldownSeconds": false,
            "blinkIntervalMilliseconds": true,
            "localOutputReassertSeconds": false,
        ])

        XCTAssertEqual(config.pollInterval, PresenceEngine.Config.defaultPollInterval)
        XCTAssertEqual(config.vadThreshold, PresenceEngine.Config.defaultVadThreshold)
        XCTAssertEqual(
            config.vadMinimumActiveMilliseconds,
            PresenceEngine.Config.defaultVadMinimumActiveMilliseconds
        )
        XCTAssertEqual(
            config.recentVoiceBlinkSeconds,
            PresenceEngine.Config.defaultRecentVoiceBlinkSeconds
        )
        XCTAssertEqual(
            config.voiceCooldownSeconds,
            PresenceEngine.Config.defaultVoiceCooldownSeconds
        )
        XCTAssertEqual(
            config.blinkIntervalMilliseconds,
            PresenceEngine.Config.defaultBlinkIntervalMilliseconds
        )
        XCTAssertEqual(
            config.localOutputReassertSeconds,
            PresenceEngine.Config.defaultLocalOutputReassertSeconds
        )
    }

    func test_init_rejectsNonFiniteRuntimeNumbers() {
        let config = PresenceEngine.Config(values: [
            "pollInterval": Double.infinity,
            "vadThreshold": Double.nan,
            "vadMinimumActiveMilliseconds": Double.infinity,
            "recentVoiceBlinkSeconds": Double.infinity,
            "voiceCooldownSeconds": Double.nan,
            "blinkIntervalMilliseconds": Double.infinity,
            "localOutputReassertSeconds": Double.nan,
        ])

        XCTAssertEqual(config.pollInterval, PresenceEngine.Config.defaultPollInterval)
        XCTAssertEqual(config.vadThreshold, PresenceEngine.Config.defaultVadThreshold)
        XCTAssertEqual(
            config.vadMinimumActiveMilliseconds,
            PresenceEngine.Config.defaultVadMinimumActiveMilliseconds
        )
        XCTAssertEqual(
            config.recentVoiceBlinkSeconds,
            PresenceEngine.Config.defaultRecentVoiceBlinkSeconds
        )
        XCTAssertEqual(
            config.voiceCooldownSeconds,
            PresenceEngine.Config.defaultVoiceCooldownSeconds
        )
        XCTAssertEqual(
            config.blinkIntervalMilliseconds,
            PresenceEngine.Config.defaultBlinkIntervalMilliseconds
        )
        XCTAssertEqual(
            config.localOutputReassertSeconds,
            PresenceEngine.Config.defaultLocalOutputReassertSeconds
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

    func test_init_acceptsConfiguredBlinkInterval() {
        let config = PresenceEngine.Config(values: [
            "blinkIntervalMilliseconds": 250,
        ])

        XCTAssertEqual(config.blinkIntervalMilliseconds, 250)
        XCTAssertEqual(config.blinkInterval, 0.25)
    }

    func test_init_rejectsBlinkIntervalBelowSafeMinimum() {
        let config = PresenceEngine.Config(values: [
            "blinkIntervalMilliseconds": 99,
        ])

        XCTAssertEqual(
            config.blinkIntervalMilliseconds,
            PresenceEngine.Config.defaultBlinkIntervalMilliseconds
        )
        XCTAssertEqual(config.blinkInterval, 0.75)
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
