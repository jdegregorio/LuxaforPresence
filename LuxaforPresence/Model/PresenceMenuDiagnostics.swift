import Foundation

struct PresenceMenuDiagnostics: Equatable {
    let statusTitle: String
    let outputTitle: String
    let connectionTitle: String
    let zoomTitle: String
    let microphonePermissionTitle: String
    let microphoneTitle: String
    let voiceSamplingTitle: String
    let voiceSignalTitle: String
    let lastVoiceTitle: String
    let recentVoiceRemainingTitle: String
    let cooldownRemainingTitle: String

    init(
        state: PresenceState,
        output: LightOutput?,
        snapshot: PresenceSnapshot?,
        transportMode: TransportMode = .local,
        localWebhookReachable: Bool? = nil,
        microphoneAuthorizationState: MicrophoneAuthorizationState = .unknown,
        recentVoiceSeconds: TimeInterval,
        voiceCooldownSeconds: TimeInterval,
        manualOverride: PresenceState? = nil,
        now: Date
    ) {
        statusTitle = "Status: \(state.displayName)"
        outputTitle = "Output: \(output?.menuDisplayName ?? "Unknown")"
        switch transportMode {
        case .local:
            switch localWebhookReachable {
            case true:
                connectionTitle = "Luxafor Webhook: Listening"
            case false:
                connectionTitle = "Luxafor Webhook: Not Listening — Check Luxafor Settings"
            case nil:
                connectionTitle = "Luxafor Webhook: Checking…"
            }
        case .remote:
            connectionTitle = "Luxafor Webhook: Remote"
        }
        zoomTitle = "Zoom: \(snapshot.map { $0.zoomActive ? "Active" : "Inactive" } ?? "Unknown")"
        microphonePermissionTitle = "Microphone Permission: \(microphoneAuthorizationState.displayName)"
        microphoneTitle = "Other App Input: \(snapshot.map { $0.microphoneActive ? "In Use" : "Not In Use" } ?? "Unknown")"
        if manualOverride != nil {
            voiceSamplingTitle = "Signal Sampling: Idle"
        } else {
            voiceSamplingTitle = "Signal Sampling: \(snapshot.map { $0.voiceSamplingActive ? "Active" : "Idle" } ?? "Unknown")"
        }
        voiceSignalTitle = "Input Signal: \(snapshot.map { $0.voiceCurrentlyAboveThreshold ? "Detected" : "Quiet" } ?? "Unknown")"

        let elapsed = snapshot?.lastVoiceActivityDate.map {
            max(0, now.timeIntervalSince($0))
        }
        if let elapsed {
            lastVoiceTitle = "Last Signal: \(Self.formatElapsed(elapsed)) ago"
        } else {
            lastVoiceTitle = "Last Signal: Never"
        }

        if manualOverride == nil, state == .voiceRecent, let elapsed {
            recentVoiceRemainingTitle = "Recent Signal Remaining: \(Self.formatRemaining(recentVoiceSeconds - elapsed))"
        } else {
            recentVoiceRemainingTitle = "Recent Signal Remaining: —"
        }

        if manualOverride == nil, state == .voiceCooldown, let elapsed {
            let remaining = recentVoiceSeconds + voiceCooldownSeconds - elapsed
            cooldownRemainingTitle = "Cooldown Remaining: \(Self.formatRemaining(remaining))"
        } else {
            cooldownRemainingTitle = "Cooldown Remaining: —"
        }
    }

    var titles: [String] {
        [
            statusTitle,
            outputTitle,
            connectionTitle,
            zoomTitle,
            microphonePermissionTitle,
            microphoneTitle,
            voiceSamplingTitle,
            voiceSignalTitle,
            lastVoiceTitle,
            recentVoiceRemainingTitle,
            cooldownRemainingTitle,
        ]
    }

    private static func formatElapsed(_ interval: TimeInterval) -> String {
        format(seconds: Int(max(0, interval).rounded(.down)))
    }

    private static func formatRemaining(_ interval: TimeInterval) -> String {
        format(seconds: Int(max(0, interval).rounded(.up)))
    }

    private static func format(seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
    }
}
