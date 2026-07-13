import XCTest
@testable import LuxaforPresence

final class PresenceMenuDiagnosticsTests: XCTestCase {
    func test_voiceRecent_rendersSignalsLastVoiceAndBlinkCadence() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let snapshot = PresenceSnapshot(
            state: .voiceRecent,
            zoomActive: true,
            microphoneActive: true,
            voiceCurrentlyAboveThreshold: true,
            lastVoiceActivityDate: now.addingTimeInterval(-12),
            evaluatedAt: now,
            decisionPath: .recentVoice
        )

        let diagnostics = PresenceMenuDiagnostics(
            state: .voiceRecent,
            output: .blink(color: .red, interval: 0.75),
            snapshot: snapshot,
            recentVoiceBlinkSeconds: 300,
            voiceCooldownSeconds: 300,
            now: now
        )

        XCTAssertEqual(diagnostics.statusTitle, "Status: Voice Recent (Flashing Red)")
        XCTAssertEqual(diagnostics.outputTitle, "Output: Flashing Red (750 ms)")
        XCTAssertEqual(diagnostics.zoomTitle, "Zoom: Active")
        XCTAssertEqual(diagnostics.microphoneTitle, "Microphone: In Use")
        XCTAssertEqual(diagnostics.voiceSignalTitle, "Voice Signal: Active")
        XCTAssertEqual(diagnostics.lastVoiceTitle, "Last Voice: 12s ago")
        XCTAssertEqual(diagnostics.flashingRemainingTitle, "Flashing Remaining: 4m 48s")
        XCTAssertEqual(diagnostics.cooldownRemainingTitle, "Cooldown Remaining: —")
    }

    func test_voiceCooldown_rendersRemainingCooldown() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let snapshot = PresenceSnapshot(
            state: .voiceCooldown,
            zoomActive: true,
            microphoneActive: false,
            voiceCurrentlyAboveThreshold: false,
            lastVoiceActivityDate: now.addingTimeInterval(-420),
            evaluatedAt: now,
            decisionPath: .voiceCooldown
        )

        let diagnostics = PresenceMenuDiagnostics(
            state: .voiceCooldown,
            output: .solid(.red),
            snapshot: snapshot,
            recentVoiceBlinkSeconds: 300,
            voiceCooldownSeconds: 300,
            now: now
        )

        XCTAssertEqual(diagnostics.outputTitle, "Output: Solid Red")
        XCTAssertEqual(diagnostics.lastVoiceTitle, "Last Voice: 7m ago")
        XCTAssertEqual(diagnostics.flashingRemainingTitle, "Flashing Remaining: —")
        XCTAssertEqual(diagnostics.cooldownRemainingTitle, "Cooldown Remaining: 3m")
    }

    func test_unknownStartup_hasSafeDiagnosticPlaceholders() {
        let diagnostics = PresenceMenuDiagnostics(
            state: .unknown,
            output: nil,
            snapshot: nil,
            recentVoiceBlinkSeconds: 300,
            voiceCooldownSeconds: 300,
            now: Date()
        )

        XCTAssertEqual(diagnostics.zoomTitle, "Zoom: Unknown")
        XCTAssertEqual(diagnostics.microphoneTitle, "Microphone: Unknown")
        XCTAssertEqual(diagnostics.lastVoiceTitle, "Last Voice: Never")
    }

    func test_countdowns_clampAtExactTimelineBoundaries() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let recentSnapshot = PresenceSnapshot(
            state: .voiceRecent,
            zoomActive: true,
            microphoneActive: false,
            voiceCurrentlyAboveThreshold: false,
            lastVoiceActivityDate: now.addingTimeInterval(-300),
            evaluatedAt: now,
            decisionPath: .recentVoice
        )
        let cooldownSnapshot = PresenceSnapshot(
            state: .voiceCooldown,
            zoomActive: true,
            microphoneActive: false,
            voiceCurrentlyAboveThreshold: false,
            lastVoiceActivityDate: now.addingTimeInterval(-600),
            evaluatedAt: now,
            decisionPath: .voiceCooldown
        )

        let recent = PresenceMenuDiagnostics(
            state: .voiceRecent,
            output: .blink(color: .red, interval: 0.75),
            snapshot: recentSnapshot,
            recentVoiceBlinkSeconds: 300,
            voiceCooldownSeconds: 300,
            now: now
        )
        let cooldown = PresenceMenuDiagnostics(
            state: .voiceCooldown,
            output: .solid(.red),
            snapshot: cooldownSnapshot,
            recentVoiceBlinkSeconds: 300,
            voiceCooldownSeconds: 300,
            now: now
        )

        XCTAssertEqual(recent.flashingRemainingTitle, "Flashing Remaining: 0s")
        XCTAssertEqual(cooldown.cooldownRemainingTitle, "Cooldown Remaining: 0s")
    }

    func test_manualVoiceOverride_doesNotShowAutomaticTimelineCountdown() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let snapshot = PresenceSnapshot(
            state: .zoomQuiet,
            zoomActive: true,
            microphoneActive: false,
            voiceCurrentlyAboveThreshold: false,
            lastVoiceActivityDate: now.addingTimeInterval(-12),
            evaluatedAt: now,
            decisionPath: .zoomQuiet
        )

        let diagnostics = PresenceMenuDiagnostics(
            state: .voiceRecent,
            output: .blink(color: .red, interval: 0.75),
            snapshot: snapshot,
            recentVoiceBlinkSeconds: 300,
            voiceCooldownSeconds: 300,
            manualOverride: .voiceRecent,
            now: now
        )

        XCTAssertEqual(diagnostics.lastVoiceTitle, "Last Voice: 12s ago")
        XCTAssertEqual(diagnostics.flashingRemainingTitle, "Flashing Remaining: —")
        XCTAssertEqual(diagnostics.cooldownRemainingTitle, "Cooldown Remaining: —")
    }

    func test_manualResetSnapshot_showsClearedVoiceDiagnostics() {
        let diagnostics = PresenceMenuDiagnostics(
            state: .voiceCooldown,
            output: .solid(.red),
            snapshot: nil,
            recentVoiceBlinkSeconds: 300,
            voiceCooldownSeconds: 300,
            manualOverride: .voiceCooldown,
            now: Date()
        )

        XCTAssertEqual(diagnostics.lastVoiceTitle, "Last Voice: Never")
        XCTAssertEqual(diagnostics.flashingRemainingTitle, "Flashing Remaining: —")
        XCTAssertEqual(diagnostics.cooldownRemainingTitle, "Cooldown Remaining: —")
    }
}
