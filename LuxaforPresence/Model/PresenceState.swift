enum PresenceState: String {
    case available
    case zoomQuiet
    case voiceRecent
    case voiceCooldown
    case unknown

    var displayName: String {
        switch self {
        case .available:
            return "Available (Off)"
        case .zoomQuiet:
            return "Zoom Quiet (Yellow)"
        case .voiceRecent:
            return "Voice Recent (Red)"
        case .voiceCooldown:
            return "Voice Cooldown (Red)"
        case .unknown:
            return "Unknown"
        }
    }
}
