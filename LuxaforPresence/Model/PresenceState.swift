enum PresenceState: String {
    case available
    case zoomQuiet
    case voiceRecent
    case voiceCooldown
    case unknown

    var displayName: String {
        switch self {
        case .available:
            return "Available"
        case .zoomQuiet:
            return "Zoom Quiet"
        case .voiceRecent:
            return "Signal Recent"
        case .voiceCooldown:
            return "Signal Cooldown"
        case .unknown:
            return "Unknown"
        }
    }
}
