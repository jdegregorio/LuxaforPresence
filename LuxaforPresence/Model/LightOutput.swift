import Foundation

/// The logical light output requested by the presence state machine.
enum LightOutput: Equatable {
    case off
    case solid(LuxaforColor)

    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .solid(let color):
            return "Solid \(color.displayName)"
        }
    }

    var logMode: String {
        switch self {
        case .off:
            return "off"
        case .solid(let color):
            return "solid#\(color.hex)"
        }
    }

    var menuDisplayName: String {
        displayName
    }
}
