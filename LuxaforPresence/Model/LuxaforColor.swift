import Foundation

/// An exact 24-bit color sent to the Luxafor solid-color endpoint.
struct LuxaforColor: Equatable, Hashable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    static let off = LuxaforColor(red: 0, green: 0, blue: 0)
    static let red = LuxaforColor(red: 255, green: 0, blue: 0)
    static let orange = LuxaforColor(red: 255, green: 140, blue: 0)
    static let yellow = LuxaforColor(red: 255, green: 255, blue: 0)
    static let purple = LuxaforColor(red: 139, green: 92, blue: 246)

    init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(hexString: String) {
        let normalized = hexString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard normalized.count == 6,
              let value = UInt32(normalized, radix: 16) else {
            return nil
        }
        self.init(
            red: UInt8((value >> 16) & 0xFF),
            green: UInt8((value >> 8) & 0xFF),
            blue: UInt8(value & 0xFF)
        )
    }

    var hex: String {
        String(format: "%02X%02X%02X", red, green, blue)
    }

    var localHex: String {
        "#\(hex)"
    }

    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .red:
            return "Red (\(localHex))"
        case .orange:
            return "Orange (\(localHex))"
        case .yellow:
            return "Yellow (\(localHex))"
        case .purple:
            return "Purple (\(localHex))"
        default:
            return localHex
        }
    }

    func applyingBrightness(_ brightness: Double) -> LuxaforColor {
        let normalizedBrightness = brightness.isFinite
            ? min(max(brightness, 0), 1)
            : 1
        return LuxaforColor(
            red: Self.scaled(red, by: normalizedBrightness),
            green: Self.scaled(green, by: normalizedBrightness),
            blue: Self.scaled(blue, by: normalizedBrightness)
        )
    }

    private static func scaled(_ component: UInt8, by brightness: Double) -> UInt8 {
        UInt8((Double(component) * brightness).rounded())
    }
}
