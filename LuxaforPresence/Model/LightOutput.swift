import Foundation

/// The logical light behavior requested by the presence state machine.
///
/// Transports deliberately expose only a solid-color operation. Animated
/// outputs are expanded into solid-color phases by `LightOutputController`.
enum LightOutput: Equatable {
    case off
    case solid(LuxaforColor)
    case blink(color: LuxaforColor, interval: TimeInterval)

    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .solid(let color) where color == .yellow:
            return "Solid Yellow"
        case .solid(let color) where color == .red:
            return "Solid Red"
        case .solid(let color) where color == .orange:
            return "Solid Orange"
        case .solid(let color) where color == .purple:
            return "Solid Purple"
        case .solid:
            return "Solid Custom Color"
        case .blink(let color, _) where color == .red:
            return "Flashing Red"
        case .blink:
            return "Flashing Custom Color"
        }
    }

    var logMode: String {
        switch self {
        case .off:
            return "off"
        case .solid(let color):
            return "solid#\(color.hex)"
        case .blink(let color, let interval):
            return "blink#\(color.hex)@\(String(format: "%.3f", interval))s"
        }
    }

    var menuDisplayName: String {
        switch self {
        case .blink(_, let interval):
            return "\(displayName) (\(Int((interval * 1_000).rounded())) ms)"
        default:
            return displayName
        }
    }
}

extension PresenceState {
    var lightOutput: LightOutput {
        switch self {
        case .available, .unknown:
            return .off
        case .zoomQuiet:
            return .solid(.yellow)
        case .voiceRecent:
            return .solid(.red)
        case .voiceCooldown:
            return .solid(.orange)
        }
    }
}
