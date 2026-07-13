import Foundation

enum PresenceDecisionPath: String, Equatable {
    case noCommunicationContext
    case recentVoice
    case voiceCooldown
    case zoomQuiet
    case available
}

/// An immutable record of the signals used for one automatic presence decision.
///
/// Snapshots are emitted for every automatic evaluation, even when the resulting
/// state is unchanged. Manual overrides bypass signal reads and therefore do not
/// produce a snapshot.
struct PresenceSnapshot: Equatable {
    let state: PresenceState
    let zoomActive: Bool
    let microphoneActive: Bool
    let voiceCurrentlyAboveThreshold: Bool
    let lastVoiceActivityDate: Date?
    let evaluatedAt: Date
    let decisionPath: PresenceDecisionPath

    var secondsSinceVoiceActivity: TimeInterval? {
        lastVoiceActivityDate.map { max(0, evaluatedAt.timeIntervalSince($0)) }
    }
}
