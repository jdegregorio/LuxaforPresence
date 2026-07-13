import Foundation

/// The logical light behavior requested by the presence state machine.
///
/// Transports deliberately expose only a solid-color operation. Animated
/// outputs are expanded into solid-color phases by `LightOutputController`.
enum LightOutput: Equatable {
    case off
    case solid(LuxaforColor)
    case blink(color: LuxaforColor, interval: TimeInterval)
}

extension PresenceState {
    func lightOutput(blinkInterval: TimeInterval) -> LightOutput {
        switch self {
        case .available, .unknown:
            return .off
        case .zoomQuiet:
            return .solid(.yellow)
        case .voiceRecent:
            return .blink(color: .red, interval: blinkInterval)
        case .voiceCooldown:
            return .solid(.red)
        }
    }
}
