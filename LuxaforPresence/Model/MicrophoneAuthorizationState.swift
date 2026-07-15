enum MicrophoneAuthorizationState: String, Equatable {
    case authorized
    case denied
    case restricted
    case notDetermined
    case disabled
    case unknown

    var displayName: String {
        switch self {
        case .authorized:
            return "Authorized"
        case .denied:
            return "Denied — Open Privacy Settings"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Waiting for Approval"
        case .disabled:
            return "Disabled in Config"
        case .unknown:
            return "Unknown"
        }
    }
}
