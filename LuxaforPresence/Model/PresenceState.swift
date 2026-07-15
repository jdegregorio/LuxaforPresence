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
            return "Signal Recent (Red)"
        case .voiceCooldown:
            return "Signal Cooldown (Orange)"
        case .unknown:
            return "Unknown"
        }
    }
}
