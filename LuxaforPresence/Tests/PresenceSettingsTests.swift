import XCTest
@testable import LuxaforPresence

final class PresenceSettingsTests: XCTestCase {
    func test_draftValidatedConfig_roundTripsEveryUserSetting() throws {
        var draft = PresenceSettingsDraft(
            config: PresenceEngine.Config(values: [:])
        )
        draft.transportMode = .remote
        draft.remoteWebhookUserID = "real-user-id"
        draft.localWebhookBaseURL = "http://127.0.0.1:6000"
        draft.localWebhookToken = "token"
        draft.pollInterval = 3
        draft.detectZoom = false
        draft.vadEnabled = false
        draft.vadThreshold = 0.02
        draft.zoomVadThreshold = 0.04
        draft.vadMinimumActiveMilliseconds = 400
        draft.recentVoiceSeconds = 90
        draft.voiceCooldownSeconds = 120
        draft.localOutputHeartbeatEnabled = true
        draft.localOutputReassertSeconds = 45
        draft.outputBrightness = 0.5
        draft.availableColor = .init(red: 1, green: 2, blue: 3)
        draft.zoomQuietColor = .init(red: 4, green: 5, blue: 6)
        draft.recentVoiceColor = .init(red: 7, green: 8, blue: 9)
        draft.voiceCooldownColor = .init(red: 10, green: 11, blue: 12)

        let config = try draft.validatedConfig()

        XCTAssertEqual(config.transportMode, .remote)
        XCTAssertEqual(config.remoteWebhookUserId, "real-user-id")
        XCTAssertEqual(config.localWebhookBaseUrl, "http://127.0.0.1:6000")
        XCTAssertEqual(config.localWebhookToken, "token")
        XCTAssertEqual(config.pollInterval, 3)
        XCTAssertFalse(config.detectZoom)
        XCTAssertFalse(config.vadEnabled)
        XCTAssertEqual(config.vadThreshold, 0.02)
        XCTAssertEqual(config.zoomVadThreshold, 0.04)
        XCTAssertEqual(config.vadMinimumActiveMilliseconds, 400)
        XCTAssertEqual(config.recentVoiceSeconds, 90)
        XCTAssertEqual(config.voiceCooldownSeconds, 120)
        XCTAssertTrue(config.localOutputHeartbeatEnabled)
        XCTAssertEqual(config.localOutputReassertSeconds, 45)
        XCTAssertEqual(config.outputBrightness, 0.5)
        XCTAssertEqual(config.availableColor, .init(red: 1, green: 2, blue: 3))
        XCTAssertEqual(config.zoomQuietColor, .init(red: 4, green: 5, blue: 6))
        XCTAssertEqual(config.recentVoiceColor, .init(red: 7, green: 8, blue: 9))
        XCTAssertEqual(config.voiceCooldownColor, .init(red: 10, green: 11, blue: 12))
    }

    func test_defaults_loadsBundledTimingAndColors() {
        let draft = PresenceSettingsDraft.defaults()

        XCTAssertEqual(draft.recentVoiceSeconds, 300)
        XCTAssertEqual(draft.voiceCooldownSeconds, 300)
        XCTAssertEqual(draft.zoomVadThreshold, 0.02)
        XCTAssertEqual(draft.availableColor, .off)
        XCTAssertEqual(draft.zoomQuietColor, .yellow)
        XCTAssertEqual(draft.recentVoiceColor, .red)
        XCTAssertEqual(draft.voiceCooldownColor, .orange)
    }

    func test_validatedConfig_rejectsInvalidTimelineDurations() {
        var draft = PresenceSettingsDraft(
            config: PresenceEngine.Config(values: [:])
        )
        draft.recentVoiceSeconds = -1

        XCTAssertThrowsError(try draft.validatedConfig()) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Recent signal duration must be zero seconds or more."
            )
        }
    }

    func test_validatedConfig_rejectsPlaceholderRemoteUserID() {
        var draft = PresenceSettingsDraft(
            config: PresenceEngine.Config(values: [:])
        )
        draft.transportMode = .remote

        XCTAssertThrowsError(try draft.validatedConfig()) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Remote transport requires a real Luxafor webhook user ID."
            )
        }
    }
}
