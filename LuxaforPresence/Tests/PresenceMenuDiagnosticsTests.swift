import XCTest
@testable import LuxaforPresence

final class PresenceMenuDiagnosticsTests: XCTestCase {
    func test_voiceRecent_rendersSignalsLastSignalAndRedOutput() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let snapshot = PresenceSnapshot(
            state: .voiceRecent,
            zoomActive: true,
            microphoneActive: true,
            voiceSamplingActive: true,
            voiceCurrentlyAboveThreshold: true,
            lastVoiceActivityDate: now.addingTimeInterval(-12),
            evaluatedAt: now,
            decisionPath: .recentVoice
        )

        let diagnostics = PresenceMenuDiagnostics(
            state: .voiceRecent,
            output: .solid(.red),
            snapshot: snapshot,
            microphoneAuthorizationState: .authorized,
            recentVoiceSeconds: 300,
            voiceCooldownSeconds: 300,
            now: now
        )

        XCTAssertEqual(diagnostics.statusTitle, "Status: Signal Recent")
        XCTAssertEqual(diagnostics.outputTitle, "Output: Solid Red (#FF0000)")
        XCTAssertEqual(diagnostics.connectionTitle, "Luxafor Webhook: Checking…")
        XCTAssertEqual(diagnostics.zoomTitle, "Zoom: Active")
        XCTAssertEqual(diagnostics.microphonePermissionTitle, "Microphone Permission: Authorized")
        XCTAssertEqual(diagnostics.microphoneTitle, "Other App Input: In Use")
        XCTAssertEqual(diagnostics.voiceSamplingTitle, "Signal Sampling: Active")
        XCTAssertEqual(diagnostics.voiceSignalTitle, "Input Signal: Detected")
        XCTAssertEqual(diagnostics.lastVoiceTitle, "Last Signal: 12s ago")
        XCTAssertEqual(diagnostics.recentVoiceRemainingTitle, "Recent Signal Remaining: 4m 48s")
        XCTAssertEqual(diagnostics.cooldownRemainingTitle, "Cooldown Remaining: —")
    }

    func test_voiceCooldown_rendersRemainingCooldown() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let snapshot = PresenceSnapshot(
            state: .voiceCooldown,
            zoomActive: true,
            microphoneActive: false,
            voiceSamplingActive: false,
            voiceCurrentlyAboveThreshold: false,
            lastVoiceActivityDate: now.addingTimeInterval(-420),
            evaluatedAt: now,
            decisionPath: .voiceCooldown
        )

        let diagnostics = PresenceMenuDiagnostics(
            state: .voiceCooldown,
            output: .solid(.orange),
            snapshot: snapshot,
            recentVoiceSeconds: 300,
            voiceCooldownSeconds: 300,
            now: now
        )

        XCTAssertEqual(diagnostics.outputTitle, "Output: Solid Orange (#FF8C00)")
        XCTAssertEqual(diagnostics.lastVoiceTitle, "Last Signal: 7m ago")
        XCTAssertEqual(diagnostics.recentVoiceRemainingTitle, "Recent Signal Remaining: —")
        XCTAssertEqual(diagnostics.cooldownRemainingTitle, "Cooldown Remaining: 3m")
    }

    func test_unknownStartup_hasSafeDiagnosticPlaceholders() {
        let diagnostics = PresenceMenuDiagnostics(
            state: .unknown,
            output: nil,
            snapshot: nil,
            recentVoiceSeconds: 300,
            voiceCooldownSeconds: 300,
            now: Date()
        )

        XCTAssertEqual(diagnostics.zoomTitle, "Zoom: Unknown")
        XCTAssertEqual(diagnostics.microphonePermissionTitle, "Microphone Permission: Unknown")
        XCTAssertEqual(diagnostics.microphoneTitle, "Other App Input: Unknown")
        XCTAssertEqual(diagnostics.voiceSamplingTitle, "Signal Sampling: Unknown")
        XCTAssertEqual(diagnostics.voiceSignalTitle, "Input Signal: Unknown")
        XCTAssertEqual(diagnostics.lastVoiceTitle, "Last Signal: Never")
    }

    func test_deniedMicrophonePermission_rendersActionableStatus() {
        let diagnostics = PresenceMenuDiagnostics(
            state: .available,
            output: .off,
            snapshot: nil,
            microphoneAuthorizationState: .denied,
            recentVoiceSeconds: 300,
            voiceCooldownSeconds: 300,
            now: Date()
        )

        XCTAssertEqual(
            diagnostics.microphonePermissionTitle,
            "Microphone Permission: Denied — Open Privacy Settings"
        )
    }

    func test_localWebhookReachability_rendersActionableConnectionState() {
        let reachable = PresenceMenuDiagnostics(
            state: .available,
            output: .off,
            snapshot: nil,
            localWebhookReachable: true,
            recentVoiceSeconds: 300,
            voiceCooldownSeconds: 300,
            now: Date()
        )
        let unavailable = PresenceMenuDiagnostics(
            state: .available,
            output: .off,
            snapshot: nil,
            localWebhookReachable: false,
            recentVoiceSeconds: 300,
            voiceCooldownSeconds: 300,
            now: Date()
        )
        let remote = PresenceMenuDiagnostics(
            state: .available,
            output: .off,
            snapshot: nil,
            transportMode: .remote,
            recentVoiceSeconds: 300,
            voiceCooldownSeconds: 300,
            now: Date()
        )

        XCTAssertEqual(reachable.connectionTitle, "Luxafor Webhook: Listening")
        XCTAssertEqual(
            unavailable.connectionTitle,
            "Luxafor Webhook: Not Listening — Check Luxafor Settings"
        )
        XCTAssertEqual(remote.connectionTitle, "Luxafor Webhook: Remote")
    }

    func test_countdowns_clampAtExactTimelineBoundaries() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let recentSnapshot = PresenceSnapshot(
            state: .voiceRecent,
            zoomActive: true,
            microphoneActive: false,
            voiceSamplingActive: false,
            voiceCurrentlyAboveThreshold: false,
            lastVoiceActivityDate: now.addingTimeInterval(-300),
            evaluatedAt: now,
            decisionPath: .recentVoice
        )
        let cooldownSnapshot = PresenceSnapshot(
            state: .voiceCooldown,
            zoomActive: true,
            microphoneActive: false,
            voiceSamplingActive: false,
            voiceCurrentlyAboveThreshold: false,
            lastVoiceActivityDate: now.addingTimeInterval(-600),
            evaluatedAt: now,
            decisionPath: .voiceCooldown
        )

        let recent = PresenceMenuDiagnostics(
            state: .voiceRecent,
            output: .solid(.red),
            snapshot: recentSnapshot,
            recentVoiceSeconds: 300,
            voiceCooldownSeconds: 300,
            now: now
        )
        let cooldown = PresenceMenuDiagnostics(
            state: .voiceCooldown,
            output: .solid(.orange),
            snapshot: cooldownSnapshot,
            recentVoiceSeconds: 300,
            voiceCooldownSeconds: 300,
            now: now
        )

        XCTAssertEqual(recent.recentVoiceRemainingTitle, "Recent Signal Remaining: 0s")
        XCTAssertEqual(cooldown.cooldownRemainingTitle, "Cooldown Remaining: 0s")
    }

    func test_manualVoiceOverride_doesNotShowAutomaticTimelineCountdown() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let snapshot = PresenceSnapshot(
            state: .zoomQuiet,
            zoomActive: true,
            microphoneActive: false,
            voiceSamplingActive: true,
            voiceCurrentlyAboveThreshold: false,
            lastVoiceActivityDate: now.addingTimeInterval(-12),
            evaluatedAt: now,
            decisionPath: .zoomQuiet
        )

        let diagnostics = PresenceMenuDiagnostics(
            state: .voiceRecent,
            output: .solid(.red),
            snapshot: snapshot,
            recentVoiceSeconds: 300,
            voiceCooldownSeconds: 300,
            manualOverride: .voiceRecent,
            now: now
        )

        XCTAssertEqual(diagnostics.lastVoiceTitle, "Last Signal: 12s ago")
        XCTAssertEqual(diagnostics.voiceSamplingTitle, "Signal Sampling: Idle")
        XCTAssertEqual(diagnostics.recentVoiceRemainingTitle, "Recent Signal Remaining: —")
        XCTAssertEqual(diagnostics.cooldownRemainingTitle, "Cooldown Remaining: —")
    }

    func test_manualResetSnapshot_showsClearedVoiceDiagnostics() {
        let diagnostics = PresenceMenuDiagnostics(
            state: .voiceCooldown,
            output: .solid(.orange),
            snapshot: nil,
            recentVoiceSeconds: 300,
            voiceCooldownSeconds: 300,
            manualOverride: .voiceCooldown,
            now: Date()
        )

        XCTAssertEqual(diagnostics.lastVoiceTitle, "Last Signal: Never")
        XCTAssertEqual(diagnostics.recentVoiceRemainingTitle, "Recent Signal Remaining: —")
        XCTAssertEqual(diagnostics.cooldownRemainingTitle, "Cooldown Remaining: —")
    }
}
